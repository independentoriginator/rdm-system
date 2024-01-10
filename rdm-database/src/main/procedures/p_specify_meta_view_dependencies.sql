drop procedure if exists p_detect_meta_view_dependants(
	${mainSchemaName}.meta_view.internal_name%type
	, ${mainSchemaName}.meta_schema.internal_name%type
	, ${mainSchemaName}.meta_view.is_routine%type
);

create or replace procedure p_specify_meta_view_dependencies(
	i_view_name ${mainSchemaName}.meta_view.internal_name%type
	, i_schema_name ${mainSchemaName}.meta_schema.internal_name%type
	, i_is_routine ${mainSchemaName}.meta_view.is_routine%type
	, i_treat_the_obj_as_dependent boolean -- and as master otherwise	
	, i_consider_registered_objects_only boolean = false
)
language plpgsql
as $procedure$
declare 
	l_view_id ${mainSchemaName}.meta_view.id%type;
begin
	select 
		v.id
	into 
		l_view_id
	from
		${mainSchemaName}.meta_view v 
	left join ${mainSchemaName}.meta_schema s 
		on s.id = v.schema_id 
	where 
		v.internal_name = i_view_name
		and coalesce(s.internal_name, '${mainSchemaName}') = i_schema_name
		and v.is_routine = i_is_routine
	;

	if l_view_id is null then
		raise exception 
			'The % specified is unknown: %.%'
			, case when i_is_routine then 'routine' else 'view' end
			, i_schema_name
			, i_view_name
		;
	end if;
	
	delete from 
		${mainSchemaName}.meta_view_dependency
	where 
		(
			i_treat_the_obj_as_dependent = false
			and master_view_id = l_view_id
		)
		or (
			i_treat_the_obj_as_dependent = true
			and view_id = l_view_id
		)
	;

	with 
	 	dependent_obj as ${bco_cte_materialized}(
	 		select 
				obj_oid
				, obj_name
				, obj_schema
				, obj_class
				, obj_type
				, dep_level
				, (obj_type in ('v'::"char", 'm'::"char")) as is_view
	 		from
				${mainSchemaName}.f_sys_obj_dependency(
					i_obj_name => i_view_name
					, i_schema_name => i_schema_name
					, i_is_routine => i_is_routine
					, i_treat_the_obj_as_dependent => i_treat_the_obj_as_dependent
					, i_exclude_curr_obj => false
				)	 	
			where 
				obj_schema not like 'pg\_%'
				and obj_schema not in ('information_schema', 'public')
				and (obj_name not like 'v\_meta\_%' or obj_schema <> '${mainSchemaName}')
	 	)
		, meta_view as ${bco_cte_materialized}(
			select 
				v.id as view_id
				, v.internal_name as view_name
				, coalesce(s.internal_name, '${mainSchemaName}') as view_schema
				, v.schema_id
				, v.is_external
				, v.is_routine 
				, case 
					when v.is_routine 
					then 'routine'::name 
					else 'relation'::name 
				end as view_class
			from
				${mainSchemaName}.meta_view v 
			left join ${mainSchemaName}.meta_schema s 
				on s.id = v.schema_id 
		)
		, meta_type as ${bco_cte_materialized}(
			select 
				t.id
				, t.internal_name
				, coalesce(s.internal_name, '${mainSchemaName}') as schema_name
				, 'relation'::name as obj_class
			from 
				${mainSchemaName}.meta_type t
			left join ${mainSchemaName}.meta_schema s 
				on s.id = t.schema_id
			where 
				not t.is_abstract
		)
		, dependency as ${bco_cte_materialized}(
			select
				dependent_obj.*
				, case dependent_obj.obj_class 
					when 'routine'::name then true 
					else false  
				end as is_routine
				, v.view_id 
				, t.id as type_id
				, coalesce(v.schema_id, s.id) as schema_id  
				, v.is_external
				, case 
					when (v.view_id is null or v.is_external) and dependent_obj.obj_oid is not null then
						format(E'set role %s;\n', obj_owner.rolname) 
						|| case dependent_obj.obj_class
							when 'relation' then 
								${mainSchemaName}.f_view_definition(
									i_view_oid => dependent_obj.obj_oid
									, i_enforce_nodata_for_matview => true
								)
							when 'routine' then
								pg_catalog.pg_get_functiondef(dependent_obj.obj_oid)
						end
						|| E';\nreset role;'
				end as external_view_def
			from 
				dependent_obj
			left join meta_view v 
				on v.view_name = dependent_obj.obj_name 
				and v.view_schema = dependent_obj.obj_schema
				and v.view_class = dependent_obj.obj_class
			left join meta_type t 
				on t.internal_name = dependent_obj.obj_name 
				and t.schema_name = dependent_obj.obj_schema
				and t.obj_class = dependent_obj.obj_class
			left join ${mainSchemaName}.meta_schema s 
				on s.internal_name = dependent_obj.obj_schema 
			left join pg_catalog.pg_class view_obj
				on view_obj.oid = dependent_obj.obj_oid 
				and dependent_obj.obj_class = 'relation'
			left join pg_catalog.pg_proc routine_obj
				on routine_obj.oid = dependent_obj.obj_oid
				and dependent_obj.obj_class = 'routine'
			left join pg_catalog.pg_roles obj_owner 
				on obj_owner.oid = coalesce(view_obj.relowner, routine_obj.proowner)
		)
		, new_external_schema as (
			insert into ${mainSchemaName}.meta_schema(
				internal_name
				, is_external
			)
			select distinct
				d.obj_schema as internal_name
				, true as is_external
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
				and i_consider_registered_objects_only = false
			returning id, internal_name
		)
		, new_external_view as (
			insert into ${mainSchemaName}.meta_view(
				internal_name
				, schema_id
				, query
				, is_external
				, is_routine
				, is_created
				, modification_time
			)
			select distinct
				d.obj_name as internal_name
				, coalesce(d.schema_id, ns.id) as schema_id
				, d.external_view_def as query
				, true as is_external
				, d.is_routine
				, d.is_routine
				, current_timestamp
			from 
				dependency d 
			left join new_external_schema ns 
				on ns.internal_name = d.obj_schema
			where
				d.view_id is null 
				and i_consider_registered_objects_only = false
			returning id, internal_name, schema_id, is_routine
		)
		, actualized_external_view as (
			update ${mainSchemaName}.meta_view v
			set 
				query = d.external_view_def
				, is_disabled = false
				, modification_time = current_timestamp
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
		, master_type_id
		, level
	)
	select 
		view_id
		, master_view_id
		, master_type_id
		, level
	from (
		select
			case i_treat_the_obj_as_dependent
				when true then master_view.view_id
				else coalesce(dependent_obj.view_id, ev.id)
			end as view_id
			, case i_treat_the_obj_as_dependent
				when true then coalesce(dependent_obj.view_id, ev.id)
				else master_view.view_id
			end as master_view_id
			, null::${type.id} as master_type_id
			, min(abs(dependent_obj.dep_level)) as level
		from 
			dependency master_view
		join dependency dependent_obj
			on dependent_obj.dep_level <> 0
		left join ${mainSchemaName}.meta_schema s 
			on s.internal_name = dependent_obj.obj_schema 
		left join new_external_schema es 
			on es.internal_name = dependent_obj.obj_schema
		left join new_external_view ev 
			on ev.internal_name = dependent_obj.obj_name
			and ev.schema_id = coalesce(s.id, es.id)
			and ev.is_routine = dependent_obj.is_routine
		left join actualized_external_view aev
			on aev.id = dependent_obj.view_id
		where
			master_view.dep_level = 0
			and master_view.is_view
		group by
			coalesce(dependent_obj.view_id, ev.id)
			, master_view.view_id
		union all
		select
			master_view.view_id
			, null::${type.id} as master_view_id
			, dependent_obj.type_id as master_type_id
			, min(abs(dependent_obj.dep_level)) as level
		from 
			dependency master_view
		join dependency dependent_obj
			on dependent_obj.dep_level <> 0
		where
			master_view.dep_level = 0
			and master_view.is_view
			and dependent_obj.type_id is not null
			and i_treat_the_obj_as_dependent
		group by
			master_view.view_id
			, dependent_obj.type_id
	) t 
	where 
		view_id is not null 
		and coalesce(master_view_id, master_type_id) is not null		
	;	
end
$procedure$;			

comment on procedure p_specify_meta_view_dependencies(
	${mainSchemaName}.meta_view.internal_name%type
	, ${mainSchemaName}.meta_schema.internal_name%type
	, ${mainSchemaName}.meta_view.is_routine%type
	, boolean
	, boolean
) is 'Определить зависимости метапредставления';
