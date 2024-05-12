drop procedure if exists p_detect_meta_view_dependants(
	${mainSchemaName}.meta_view.internal_name%type
	, ${mainSchemaName}.meta_schema.internal_name%type
	, ${mainSchemaName}.meta_view.is_routine%type
);

drop procedure if exists p_detect_meta_view_dependants(
	${mainSchemaName}.meta_view.internal_name%type
	, ${mainSchemaName}.meta_schema.internal_name%type
	, ${mainSchemaName}.meta_view.is_routine%type
	, boolean	
	, boolean
);

drop procedure if exists p_specify_meta_view_dependencies(
	${mainSchemaName}.meta_view.internal_name%type
	, ${mainSchemaName}.meta_schema.internal_name%type
	, ${mainSchemaName}.meta_view.is_routine%type
	, boolean	
	, boolean
);

create or replace procedure p_specify_meta_view_dependencies(
	i_views jsonb
	, i_treat_the_obj_as_dependent boolean -- and as master otherwise	
	, i_consider_registered_objects_only boolean = false
)
language plpgsql
as $procedure$
declare 
	l_view_ids ${type.id}[];
	l_view_id ${type.id};
begin
	select 
		array_agg(v.id)
	into 
		l_view_ids
	from
		${mainSchemaName}.v_meta_view v 
	join jsonb_to_recordset(i_views) as obj(obj_schema name, obj_name text, obj_class name)
		on obj.obj_name = v.internal_name  
		and obj.obj_schema = v.schema_name
		and obj.obj_class = v.obj_class
	;

	if l_view_ids is null or cardinality(l_view_ids) <> jsonb_array_length(i_views) then
		raise exception 
			'Unknown objects specified: %'
			, i_views
		;
	end if;
	
	delete from 
		${mainSchemaName}.meta_view_dependency
	where 
		(
			i_treat_the_obj_as_dependent = false
			and master_view_id = any(l_view_ids)
		)
		or (
			i_treat_the_obj_as_dependent = true
			and view_id = any(l_view_ids)
		)
	;

	with 
	 	dependent_obj as ${bco_cte_materialized}(
	 		select 
				obj_id
				, dep_obj_id
				, dep_obj_name
				, dep_obj_schema
				, dep_obj_class
				, dep_obj_type
				, dep_level
				, (dep_obj_type in ('v'::"char", 'm'::"char")) as is_view
	 		from
				${mainSchemaName}.f_sys_obj_dependency(
					i_objects => i_views
					, i_treat_the_obj_as_dependent => i_treat_the_obj_as_dependent
					, i_exclude_the_obj_specified => false
					, i_exclude_system_objects => true
				)	 	
	 	)
		, meta_view as ${bco_cte_materialized}(
			select 
				v.id as view_id
				, v.internal_name as view_name
				, v.schema_name as view_schema
				, v.schema_id
				, v.is_external
				, v.is_routine 
				, v.obj_class as view_class
				, v.view_oid
			from
				${mainSchemaName}.v_meta_view v 
		)
		, meta_type as ${bco_cte_materialized}(
			select 
				t.id
				, t.internal_name
				, t.schema_name
				, t.localization_table_name
				, 'relation'::name as obj_class
			from 
				${mainSchemaName}.v_meta_type t
		)
		, dependency as ${bco_cte_materialized}(
			select
				dependent_obj.obj_id
				, dependent_obj.dep_obj_id
				, dependent_obj.dep_obj_name
				, dependent_obj.dep_obj_schema
				, dependent_obj.dep_obj_class
				, dependent_obj.dep_obj_type
				, dependent_obj.dep_level
				, dependent_obj.is_view
				, case dependent_obj.dep_obj_class 
					when 'routine'::name then true 
					else false  
				end as is_routine
				, v.view_id 
				, coalesce(t.id, t_lc.id) as type_id
				, coalesce(v.schema_id, s.id) as schema_id  
				, v.is_external
				, case 
					when (v.view_id is null or v.is_external) and dependent_obj.dep_obj_id is not null then
						${mainSchemaName}.f_sys_obj_definition(
							i_obj_class => dependent_obj.dep_obj_class
							, i_obj_id => dependent_obj.dep_obj_id
							, i_enforce_nodata_for_matview => true
						)
				end as external_view_def
			from 
				dependent_obj
			left join meta_view v 
				on v.view_oid = dependent_obj.obj_id 
				or (
					v.view_name = dependent_obj.dep_obj_name 
					and v.view_schema = dependent_obj.dep_obj_schema
					and v.view_class = dependent_obj.dep_obj_class
				) 
			left join meta_type t 
				on t.internal_name = dependent_obj.dep_obj_name 
				and t.schema_name = dependent_obj.dep_obj_schema
				and t.obj_class = dependent_obj.dep_obj_class
			left join meta_type t_lc 
				on t_lc.localization_table_name = dependent_obj.dep_obj_name 
				and t_lc.schema_name = dependent_obj.dep_obj_schema
				and t_lc.obj_class = dependent_obj.dep_obj_class
			left join ${mainSchemaName}.meta_schema s 
				on s.internal_name = dependent_obj.dep_obj_schema 
		)
		, new_external_schema as (
			insert into 
				${mainSchemaName}.meta_schema(
					internal_name
					, is_external
				)
			select distinct
				d.dep_obj_schema as internal_name
				, true as is_external
			from 
				dependency d 
			where 	
				d.view_id is null 
				and d.dep_obj_schema not in (
					select 
						s.internal_name 
					from 
						${mainSchemaName}.meta_schema s
				)
				and i_consider_registered_objects_only = false
			returning 
				id
				, internal_name
		)
		, new_external_view as (
			insert into 
				${mainSchemaName}.meta_view(
					internal_name
					, schema_id
					, query
					, is_external
					, is_routine
					, is_created
					, modification_time
				)
			select distinct
				d.dep_obj_name as internal_name
				, coalesce(d.schema_id, ns.id) as schema_id
				, d.external_view_def as query
				, true as is_external
				, d.is_routine
				, d.is_routine
				, current_timestamp
			from 
				dependency d 
			left join new_external_schema ns 
				on ns.internal_name = d.dep_obj_schema
			where
				d.view_id is null 
				and i_consider_registered_objects_only = false
			returning 
				id
				, internal_name
				, schema_id
				, is_routine
		)
		, actualized_external_view as (
			update 
				${mainSchemaName}.meta_view v
			set 
				query = d.external_view_def
				, is_disabled = false
				, modification_time = current_timestamp
			from 
				dependency d
			where 
				v.id = d.view_id
				and d.is_external = true
			returning 
				id
		)
	insert into 
		${mainSchemaName}.meta_view_dependency(
			view_id
			, master_view_id
			, master_type_id
			, level
		)
	select 
		t.view_id
		, t.master_view_id
		, t.master_type_id
		, t.level
	from (
		select  
			t.view_id
			, t.master_view_id
			, null::${type.id} as master_type_id
			, t.level
		from (
			select
				case 
					when i_treat_the_obj_as_dependent 
					then master_view.view_id
					else coalesce(dependent_obj.view_id, ev.id)
				end as view_id
				, case 
					when i_treat_the_obj_as_dependent 
					then coalesce(dependent_obj.view_id, ev.id)
					else master_view.view_id
				end as master_view_id
				, min(abs(dependent_obj.dep_level)) as level
			from 
				dependency master_view
			join dependency dependent_obj
				on dependent_obj.obj_id = master_view.obj_id 
				and dependent_obj.dep_level <> 0
			left join ${mainSchemaName}.meta_schema s 
				on s.internal_name = dependent_obj.dep_obj_schema 
			left join new_external_schema es 
				on es.internal_name = dependent_obj.dep_obj_schema
			left join new_external_view ev 
				on ev.internal_name = dependent_obj.dep_obj_name
				and ev.schema_id = coalesce(s.id, es.id)
				and ev.is_routine = dependent_obj.is_routine
			left join actualized_external_view aev
				on aev.id = dependent_obj.view_id
			where
				master_view.dep_level = 0
				and master_view.view_id is not null
			group by
				coalesce(dependent_obj.view_id, ev.id)
				, master_view.view_id
		) t 
		where 
			t.view_id <> t.master_view_id
		union all
		select
			master_view.view_id
			, null::${type.id} as master_view_id
			, dependent_obj.type_id as master_type_id
			, min(abs(dependent_obj.dep_level)) as level
		from 
			dependency master_view
		join dependency dependent_obj
			on dependent_obj.obj_id = master_view.obj_id
			and dependent_obj.dep_level <> 0
		where
			master_view.dep_level = 0
			and master_view.view_id is not null
			and dependent_obj.type_id is not null
			and i_treat_the_obj_as_dependent
		group by
			master_view.view_id
			, dependent_obj.type_id
	) t 
	where 
		t.view_id is not null 
		and coalesce(t.master_view_id, t.master_type_id) is not null	
	;	

	if i_treat_the_obj_as_dependent then
		for l_view_id in (
			select
				v.id
			from 
				${mainSchemaName}.v_meta_view v
			where 
				v.id = any(l_view_ids)
			order by
				case when v.is_external then null else v.creation_order end
				, v.previously_defined_dependency_level
		) 
		loop		
			insert into 
				${mainSchemaName}.meta_view_dependency(
					view_id
					, master_view_id
					, master_type_id
					, level
				)
			select
				t.view_id
				, dep_inherited.master_view_id
				, dep_inherited.master_type_id
				, min(dep_inherited.level) + 1 as level
			from 
				${mainSchemaName}.meta_view_dependency t
			join ${mainSchemaName}.meta_view_dependency dep_inherited
				on dep_inherited.view_id = t.master_view_id
				and (
					dep_inherited.master_view_id <> t.view_id
					or dep_inherited.master_type_id is not null 
				)
			where 
				t.view_id = l_view_id
				and not exists (
					select 
						1
					from 
						${mainSchemaName}.meta_view_dependency dep 
					where 
						dep.view_id = t.view_id
						and (
							dep.master_view_id = dep_inherited.master_view_id
							or dep.master_type_id = dep_inherited.master_type_id
						)
				)
			group by 
				t.view_id
				, dep_inherited.master_view_id
				, dep_inherited.master_type_id
			;
		end loop;
	end if;	
end
$procedure$;			

comment on procedure p_specify_meta_view_dependencies(
	jsonb
	, boolean	
	, boolean
) is 'Определить зависимости метапредставления';
