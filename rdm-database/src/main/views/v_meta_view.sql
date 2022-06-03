create or replace view v_meta_view
as
select
	v.id
	, v.internal_name
	, ${mainSchemaName}.f_meta_view_dependency_level(
		i_view_oid => target_view.oid
	) as dependency_level
	, v.schema_id
	, coalesce(s.internal_name, '${mainSchemaName}') as schema_name
	, case when target_schema.nspname = s.internal_name then true else false end as is_schema_exists
	, case when target_view.oid is not null then true else false end as is_view_exists
	, case when target_view.relkind = 'm'::"char" then true else false end as is_materialized
	, case when v.is_created and target_view.oid is not null then true else false end as is_created
	, v.query
	, v.is_valid
	, v.refresh_time	
	, v.creation_order
	, v.is_disabled
	, v.is_external
	, (
		select 
			min(dep.level)
		from 
			${mainSchemaName}.meta_view_dependency dep
		where
			dep.view_id = v.id
	) as previously_defined_dependency_level
from 
	${mainSchemaName}.meta_view v
join ${mainSchemaName}.meta_schema s
	on s.id = v.schema_id
left join pg_catalog.pg_namespace target_schema
	on target_schema.nspname = coalesce(s.internal_name, '${mainSchemaName}')
left join pg_catalog.pg_class target_view
	on target_view.relnamespace = target_schema.oid 
	and target_view.relname = v.internal_name
	and target_view.relkind in ('v'::"char", 'm'::"char")
;