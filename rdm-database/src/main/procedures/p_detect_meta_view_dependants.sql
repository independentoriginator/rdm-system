create or replace procedure p_detect_meta_view_dependants(
	i_view_name ${mainSchemaName}.meta_view.internal_name%type
	, i_schema_name ${mainSchemaName}.meta_schema.internal_name%type
	, i_is_routine ${mainSchemaName}.meta_view.is_routine%type
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
				and v.is_routine = i_is_routine
		)
	;
	
	with 
	 	dependent_view as (
	 		select 
				obj_oid
				, obj_name
				, obj_schema
				, obj_class
				, obj_type
				, dep_level
	 		from
				${mainSchemaName}.f_sys_obj_dependency(
					i_obj_name => i_view_name
					, i_schema_name => i_schema_name
					, i_is_routine => i_is_routine
					, i_exclude_curr_obj => false
				)	 			
	 	)
		, meta_view as (
			select 
				v.id as view_id
				, v.internal_name as view_name
				, coalesce(s.internal_name, '${mainSchemaName}') as view_schema
				, v.schema_id
				, v.is_external
				, v.is_routine 
				, case when v.is_routine then 'routine'::name else 'relation'::name end as view_class
			from
				${mainSchemaName}.meta_view v 
			left join ${mainSchemaName}.meta_schema s 
				on s.id = v.schema_id 
		)
		, dependency as (
			select
				dependent_view.*
				, case dependent_view.obj_class 
					when 'routine'::name then true 
					else false  
				end as is_routine
				, v.view_id 
				, coalesce(v.schema_id, s.id) as schema_id  
				, v.is_external
				, case 
					when (v.view_id is null or v.is_external) and dependent_view.obj_oid is not null then
						case dependent_view.obj_class
							when 'relation' then 
								${mainSchemaName}.f_view_definition(
									i_view_oid => dependent_view.obj_oid
									, i_enforce_nodata_for_matview => true
								)
							when 'routine' then
								pg_catalog.pg_get_functiondef(dependent_view.obj_oid)
						end
				end as external_view_def
			from 
				dependent_view
			left join meta_view v 
				on v.view_name = dependent_view.obj_name 
				and v.view_schema = dependent_view.obj_schema
				and v.view_class = dependent_view.obj_class
			left join ${mainSchemaName}.meta_schema s 
				on s.internal_name = dependent_view.obj_schema 
		)
		, new_external_schema as (
			insert into ${mainSchemaName}.meta_schema(
				internal_name
			)
			select distinct
				d.obj_schema as internal_name
			from 
				dependency d 
			where 	
				d.view_id is null 
				and d.obj_schema not in (
					select 
						s.internal_name 
					from 
						${mainSchemaName}.meta_schema s
				)
				and d.obj_schema <> '${mainSchemaName}'
			returning id, internal_name
		)
		, new_external_view as (
			insert into ${mainSchemaName}.meta_view(
				internal_name
				, schema_id
				, query
				, is_external
				, is_routine
			)
			select distinct
				d.obj_name as internal_name
				, coalesce(d.schema_id, ns.id) as schema_id
				, d.external_view_def as query
				, true as is_external
				, d.is_routine
			from 
				dependency d 
			left join new_external_schema ns 
				on ns.internal_name = d.obj_schema
			where
				d.view_id is null 
			returning id, internal_name, schema_id, is_routine
		)
		, actualized_external_view as (
			update ${mainSchemaName}.meta_view v
			set 
				query = d.external_view_def
				, is_disabled = false
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
		on s.internal_name = dependent_view.obj_schema 
	left join new_external_schema es 
		on es.internal_name = dependent_view.obj_schema
	left join new_external_view ev 
		on ev.internal_name = dependent_view.obj_name
		and ev.schema_id = coalesce(s.id, es.id)
		and ev.is_routine = dependent_view.is_routine
	where
		master_view.dep_level = 0
	group by
		coalesce(dependent_view.view_id, ev.id)
		, master_view.view_id
	;	
end
$procedure$;			
