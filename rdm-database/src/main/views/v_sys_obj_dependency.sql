create or replace view v_sys_obj_dependency
as
select 
	dependent_obj.obj_id as dependent_obj_id
	, dependent_obj.obj_name as dependent_obj_name
	, dependent_obj.obj_schema as dependent_obj_schema
	, dependent_obj.obj_class as dependent_obj_class
	, dependent_obj.obj_type as dependent_obj_type
	, master_obj.obj_id as master_obj_id
	, master_obj.obj_name as master_obj_name
	, master_obj.obj_schema as master_obj_schema
	, master_obj.obj_class as master_obj_class
	, master_obj.obj_type as master_obj_type
from
	${mainSchemaName}.v_sys_obj dependent_obj
join pg_catalog.pg_depend pg_depend
	on pg_depend.objid = dependent_obj.obj_id
	and pg_depend.classid = dependent_obj.class_id
join ${mainSchemaName}.v_sys_obj master_obj
	on master_obj.obj_id = pg_depend.refobjid
	and master_obj.class_id = pg_depend.refclassid
	and master_obj.obj_id <> dependent_obj.obj_id					
union all
select distinct
	dependent_obj.obj_id as dependent_obj_id
	, dependent_obj.obj_name as dependent_obj_name
	, dependent_obj.obj_schema as dependent_obj_schema
	, dependent_obj.obj_class as dependent_obj_class
	, dependent_obj.obj_type as dependent_obj_type
	, master_obj.obj_id as master_obj_id
	, master_obj.obj_name as master_obj_name
	, master_obj.obj_schema as master_obj_schema
	, master_obj.obj_class as master_obj_class
	, master_obj.obj_type as master_obj_type
from
	${mainSchemaName}.v_sys_obj dependent_obj
join pg_catalog.pg_rewrite pg_rewrite
	on pg_rewrite.ev_class = dependent_obj.obj_id
join pg_catalog.pg_depend pg_depend
	on pg_depend.objid = pg_rewrite.oid
	and pg_depend.classid = 'pg_rewrite'::regclass
	-- and pg_depend.deptype = 'n' -- normal dependency
join ${mainSchemaName}.v_sys_obj master_obj
	on master_obj.obj_id = pg_depend.refobjid
	and master_obj.class_id = pg_depend.refclassid
	and master_obj.obj_id <> dependent_obj.obj_id
union
select distinct
	p.obj_id as dependent_obj_id
	, p.obj_name as dependent_obj_name
	, p.obj_schema as dependent_obj_schema
	, p.obj_class as dependent_obj_class
	, p.obj_type as dependent_obj_type
	, o.obj_id as master_obj_id
	, o.obj_name as master_obj_name
	, o.obj_schema as master_obj_schema
	, o.obj_class as master_obj_class
	, o.obj_type as master_obj_type
from 
	${mainSchemaName}.v_sys_obj p
join pg_catalog.pg_proc proc
	on proc.oid = p.obj_id
join lateral 
	unnest(
		string_to_array(
			regexp_replace(
				regexp_replace(
					lower(proc.prosrc)
					, '--.*?\n'
					, ''
					, 'g'
				)
				, '[^[:alnum:]_\.]+'
				, ' '
				, 'g'
			)
			, ' '
		)
	) as obj_candidate(obj_name)
	on true
join ${mainSchemaName}.v_sys_obj o
	on o.schema_qualified_name = obj_candidate.obj_name
	and o.obj_id <> p.obj_id 
-- ToDo: add support to the new feature for sql functions with parsing at definition time (begin atomic ... end)   
;

comment on view v_sys_obj_dependency is 'Зависимости объектов базы данных';
