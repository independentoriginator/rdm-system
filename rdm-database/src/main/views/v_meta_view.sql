create or replace view v_meta_view
as
select
	v.id
	, v.internal_name
	, v.dependency_level
	, v.schema_id
	, coalesce(s.internal_name, '${mainSchemaName}') as schema_name
	, case when target_schema.nspname = s.internal_name then true else false end as is_schema_exists
	, case when target_view.oid is not null or target_routine.oid is not null then true else false end as is_view_exists
	, case when target_view.relkind = 'm'::"char" then true else false end as is_materialized
	, case when v.is_created and (target_view.oid is not null or target_routine.oid is not null) then true else false end as is_created
	, v.query
	, v.is_valid
	, v.refresh_time	
	, v.creation_order
	, v.is_disabled
	, v.is_external
	, (
		select 
			max(dep.level)
		from 
			${mainSchemaName}.meta_view_dependency dep
		where
			dep.view_id = v.id
	) as previously_defined_dependency_level
	, v.is_routine
	, coalesce(target_view.oid, target_routine.oid) as view_oid
	, case 
		when target_view.relkind = 'v'::"char" then 'view'::text
		when target_view.relkind = 'm'::"char" then 'materialized view'::text
		when target_routine.prokind = 'p'::"char" then 'procedure'::text
		when target_routine.prokind = 'f'::"char" then 'function'::text
		when v.is_routine then 'routine'::text
		else 'view'::text
	end as view_type
	, case 
		when target_view.oid is not null then pg_catalog.obj_description(target_view.oid, 'pg_class') 
		when target_routine.oid is not null then pg_catalog.obj_description(target_routine.oid, 'pg_proc')
	end as description
	, case 
		when exists (
			select
				1
			from 
				pg_catalog.pg_index ui
			join pg_catalog.pg_class c 
				on c.oid = ui.indrelid
			join pg_catalog.pg_namespace ns
				on ns.oid = c.relnamespace
			where
				ns.nspname = target_schema.nspname
				and c.relname = target_view.relname
				and ui.indisunique
				and ui.indpred is null
		) then true
		else false
	end as has_unique_index	
	, target_view.relispopulated as is_populated
	, v.modification_time
from 
	${mainSchemaName}.meta_view v
left join ${mainSchemaName}.meta_schema s
	on s.id = v.schema_id
left join pg_catalog.pg_namespace target_schema
	on target_schema.nspname = coalesce(s.internal_name, '${mainSchemaName}')
left join pg_catalog.pg_class target_view
	on target_view.relnamespace = target_schema.oid 
	and target_view.relname = v.internal_name
	and target_view.relkind in ('v'::"char", 'm'::"char")
left join pg_catalog.pg_proc target_routine
	on target_routine.pronamespace = target_schema.oid 
	and ${mainSchemaName}.f_target_routine_name(
		i_target_routine_id => target_routine.oid
	) = v.internal_name
;