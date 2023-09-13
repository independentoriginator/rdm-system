create or replace view v_sys_schema_size
as
select 
	t.schema_name
	, t.sys_obj_type
	, t.n_relation_size
	, pg_catalog.pg_size_pretty(t.n_relation_size) as s_relation_size	
	, t.n_table_size
	, pg_catalog.pg_size_pretty(t.n_table_size) as s_table_size	
	, t.n_indexes_size
	, pg_catalog.pg_size_pretty(t.n_indexes_size) as s_indexes_size
	, t.n_total_relation_size
	, pg_catalog.pg_size_pretty(t.n_total_relation_size) as s_total_relation_size	
from (
	select 
		t.schema_name
		, t.sys_obj_type
		, sum(t.n_relation_size) as n_relation_size
		, sum(t.n_table_size) as n_table_size 
		, sum(t.n_indexes_size) as n_indexes_size 
		, sum(t.n_total_relation_size) as n_total_relation_size 
	from 
		${mainSchemaName}.v_sys_table_size t
	group by 
		t.schema_name
		, t.sys_obj_type
) t
;

comment on view v_sys_schema_size is 'Размер схем';

do $$
declare 
	l_roles text := (
		select 
			string_agg(
				r.rolname
				, ', '
			)			
		from 
			pg_catalog.pg_roles r
		left join information_schema.role_table_grants g
			on g.grantee = r.rolname
			and g.privilege_type = 'SELECT'
			and g.table_name = 'v_sys_schema_size'
			and g.table_schema = '${mainSchemaName}'
		where 
			r.rolname in (
				'${mainEndUserRole}'
				, '${etlUserRole}'
			)
	)
	;
begin
	if l_roles is not null then
		execute 
			format(
				'grant select on ${mainSchemaName}.v_sys_schema_size to %s'
				, l_roles 
			)
		;
	end if;
end
$$
;