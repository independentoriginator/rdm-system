create or replace procedure p_detect_meta_view_dependants(
	i_view_name ${mainSchemaName}.meta_view.internal_name%type
	, i_schema_name ${mainSchemaName}.meta_schema.internal_name%type
)
language plpgsql
as $procedure$
begin
	delete from 
		${mainSchemaName}.meta_view_dependency
	where 
		master_view_id in (
			select 
				v.id
			from
				${mainSchemaName}.meta_view v 
			left join ${mainSchemaName}.meta_schema s 
				on s.id = v.schema_id 
			where 
				v.internal_name = i_view_name
				and coalesce(s.internal_name, '${mainSchemaName}') = i_schema_name
		)
	;
	
	with 
		recursive dependent_view(
			cls_oid
			, cls_name
			, cls_schema
			, cls_type
			, dep_level
		) as (
			select 				
				v.oid as cls_oid
				, v.relname as cls_name
				, s.nspname as cls_schema
				, null::"char" as cls_type
				, 0 as dep_level
			from 
				pg_catalog.pg_namespace s
			join pg_catalog.pg_class v
				on v.relnamespace = s.oid
				and v.relname = i_view_name::name
			where 
				s.nspname = i_schema_name::name
			union all
			select
				dep.dependent_obj_id  as cls_oid
				, dep.dependent_obj_name as cls_name
				, dep.dependent_obj_schema as cls_schema
				, dep.dependent_obj_type as cls_type
				, dependent_view.dep_level + 1 as dep_level
			from 
				${mainSchemaName}.v_sys_obj_dependency dep
			join dependent_view 
				on dependent_view.cls_name = dep.master_obj_name 
				and dependent_view.cls_schema = dep.master_obj_schema
		)
		, meta_view as (
			select 
				v.id as view_id
				, v.internal_name as view_name
				, coalesce(s.internal_name, '${mainSchemaName}') as view_schema
				, v.schema_id
				, v.is_external 
			from
				${mainSchemaName}.meta_view v 
			left join ${mainSchemaName}.meta_schema s 
				on s.id = v.schema_id 
		)
		, dependency as (
			select
				dependent_view.*
				, v.view_id 
				, coalesce(v.schema_id, s.id) as schema_id  
				, v.is_external
				, case 
					when (v.view_id is null or v.is_external) and dependent_view.cls_oid is not null then
						${mainSchemaName}.f_view_definition(
							i_view_oid => dependent_view.cls_oid
							, i_enforce_nodata_for_matview => true
						)
				end as external_view_def
			from 
				dependent_view
			left join meta_view v 
				on v.view_name = dependent_view.cls_name 
				and v.view_schema = dependent_view.cls_schema
			left join ${mainSchemaName}.meta_schema s 
				on s.internal_name = dependent_view.cls_schema 
		)
		, new_external_schema as (
			insert into ${mainSchemaName}.meta_schema(
				internal_name
			)
			select distinct
				d.cls_schema as internal_name
			from 
				dependency d 
			where 	
				d.view_id is null 
				and d.cls_schema not in (
					select 
						s.internal_name 
					from 
						${mainSchemaName}.meta_schema s
				)
				and d.cls_schema <> '${mainSchemaName}'
			returning id, internal_name
		)
		, new_external_view as (
			insert into ${mainSchemaName}.meta_view(
				internal_name
				, schema_id
				, query
				, is_external
			)
			select 
				d.cls_name as internal_name
				, coalesce(d.schema_id, ns.id) as schema_id
				, d.external_view_def as query
				, true as is_external
			from 
				dependency d 
			left join new_external_schema ns 
				on ns.internal_name = d.cls_schema
			where
				d.view_id is null 
			returning id, internal_name, schema_id
		)
		, actualized_external_view as (
			update ${mainSchemaName}.meta_view v
			set 
				query = d.external_view_def
			from 
				dependency d
			where 
				v.id = d.view_id
				and d.is_external = true
			returning id
		)
	insert into ${mainSchemaName}.meta_view_dependency(
		view_id
		, master_view_id
		, level
	)
	select
		coalesce(dependent_view.view_id, ev.id) as view_id
		, master_view.view_id as master_view_id
		, min(dependent_view.dep_level) as level
	from 
		dependency master_view
	join dependency dependent_view
		on dependent_view.dep_level > 0
	left join ${mainSchemaName}.meta_schema s 
		on s.internal_name = dependent_view.cls_schema 
	left join new_external_schema es 
		on es.internal_name = dependent_view.cls_schema
	left join new_external_view ev 
		on ev.internal_name = dependent_view.cls_name
		and ev.schema_id = coalesce(s.id, es.id)
	where
		master_view.dep_level = 0
	group by
		coalesce(dependent_view.view_id, ev.id)
		, master_view.view_id
	;	
end
$procedure$;			
