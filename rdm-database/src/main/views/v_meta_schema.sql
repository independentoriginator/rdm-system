create or replace view v_meta_schema
as
select
	s.id
	, s.internal_name
	, (target_schema.oid is not null) as is_schema_exists
	, schema_descr.lc_string as schema_description
	, target_schema_descr.description as target_schema_description
	, missed_usage_privileges.user_roles as missed_usage_privilege_roles 
	, case 
		when target_schema.oid is null
			or nullif(schema_descr.lc_string, target_schema_descr.description) is not null
			or cardinality(missed_usage_privileges.user_roles) > 0
		then false
		else true
	end as is_built
	, 0 as ordinal_num
	, s.is_external
	, s.is_disabled
from ( 
	select
		s.id
		, s.internal_name
		, s.is_external
		, s.is_disabled
	from 
		${mainSchemaName}.meta_schema s
	union
	select 
		(select id from ${mainSchemaName}.meta_schema where internal_name = '${mainSchemaName}') as id
		, '${mainSchemaName}' as internal_name
		, false as is_external
		, false as is_disabled
	union
	select 
		(select id from ${mainSchemaName}.meta_schema where internal_name = '${stagingSchemaName}') as id
		, '${stagingSchemaName}' as internal_name
		, false as is_external
		, false as is_disabled
) s
left join pg_catalog.pg_namespace target_schema
	on target_schema.nspname = s.internal_name
join ${mainSchemaName}.meta_type meta_type
	on meta_type.internal_name = 'meta_schema' 
left join ${mainSchemaName}.meta_attribute name_attr
	on name_attr.master_id = meta_type.id
	and name_attr.internal_name = 'name'
left join ${mainSchemaName}.meta_schema_lc schema_descr
	on schema_descr.master_id = s.id
	and schema_descr.attr_id = name_attr.id
	and schema_descr.lang_id = ${mainSchemaName}.f_default_language_id()
	and schema_descr.is_default_value = true
left join pg_catalog.pg_description target_schema_descr
	on target_schema_descr.objoid = target_schema.oid
left join lateral (
	select 
		array_agg(user_role.name) as user_roles
	from (
		values (nullif('${etlUserRole}', '')), (nullif('${mainEndUserRole}', ''))
	) as user_role(name)
	where 
		user_role.name is not null
		and target_schema.oid is not null
		and not pg_catalog.has_schema_privilege(user_role.name, s.internal_name, 'USAGE')
) missed_usage_privileges
	on true
;

comment on view v_meta_schema is 'Метасхемы';
