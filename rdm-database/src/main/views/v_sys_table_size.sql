create or replace view v_sys_table_size
as
select 
	t.schema_name
	, t.table_name
	, t.sys_obj_type
	, t.n_relation_size
	, t.s_relation_size	
	, t.n_table_size
	, t.s_table_size	
	, t.n_indexes_size
	, t.s_indexes_size
	, t.n_total_relation_size
	, t.s_total_relation_size
	, t.table_id
from 
	${mainSchemaName}.f_sys_table_size() t
;

comment on view v_sys_table_size is 'Размер таблиц';

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
			and g.table_name = 'v_sys_table_size'
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
				'grant select on ${mainSchemaName}.v_sys_table_size to %s'
				, l_roles 
			)
		;
	end if;
end
$$
;