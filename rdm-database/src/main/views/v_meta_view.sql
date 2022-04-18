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
	, type_name.lc_string as view_description
	, target_view_descr.description target_view_description
	, case when v.is_created and target_view.oid is not null then true else false end as is_created
	, v.query	
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
join ${mainSchemaName}.meta_type meta_type
	on meta_type.internal_name = 'meta_type' 
left join ${mainSchemaName}.meta_attribute name_attr
	on name_attr.master_id = meta_type.id
	and name_attr.internal_name = 'name'
left join ${mainSchemaName}.meta_type_lc type_name
	on type_name.master_id = v.id
	and type_name.attr_id = name_attr.id
	and type_name.lang_id = ${mainSchemaName}.f_default_language_id()
	and type_name.is_default_value = true
left join pg_catalog.pg_description target_view_descr 
	on target_view_descr.objoid = target_view.oid
	and target_view_descr.classoid = 'pg_class'::regclass
	and target_view_descr.objsubid = 0
;