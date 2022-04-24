create or replace view v_sys_obj_dependency
as
select distinct
	dependent_cls.oid as dependent_cls_oid
	, dependent_cls.relname as dependent_cls_name
	, dependent_cls_ns.nspname as dependent_cls_schema
	, dependent_cls.relkind as dependent_cls_relkind
	, master_cls.oid as master_cls_oid
	, master_cls.relname as master_cls_name
	, master_cls_ns.nspname as master_cls_schema
	, master_cls.relkind as master_cls_relkind
from
	pg_catalog.pg_class dependent_cls
join pg_catalog.pg_namespace dependent_cls_ns
	on dependent_cls_ns.oid = dependent_cls.relnamespace
join pg_catalog.pg_rewrite pg_rewrite
	on pg_rewrite.ev_class = dependent_cls.oid
join pg_catalog.pg_depend pg_depend
	on pg_depend.objid = pg_rewrite.oid
join pg_catalog.pg_class master_cls 
	on master_cls.oid = pg_depend.refobjid
	and master_cls.oid <> dependent_cls.oid					
join pg_catalog.pg_namespace master_cls_ns
	on master_cls_ns.oid = master_cls.relnamespace
where 
	pg_depend.deptype = 'n' 
	and pg_depend.classid = 'pg_rewrite'::regclass
;