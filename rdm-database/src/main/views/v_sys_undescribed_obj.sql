create or replace view v_sys_undescribed_obj
as
select
	'schema' as obj_type
	, o.nspname as schema_name
	, o.nspname as obj_name
	, d.description 
	, (d.description is null) as is_undescribed
	, null::integer as undescribed_column_count
from 
	pg_catalog.pg_namespace o 
left join pg_catalog.pg_description d 
	on d.objoid = o.oid
where 
	o.nspname not similar to 'pg\_%|information_schema|public'
union all
select
	case 
		when o.relkind = any(array['r', 'p']::char[]) then 'table'
		when o.relkind = any(array['v', 'm']::char[]) then 'view'
		else 'relation'
	end as obj_type
	, s.nspname as schema_name
	, o.relname as obj_name
	, d.description 
	, (d.description is null) as is_undescribed
	, (
		select 
			count(*)
		from 
			pg_catalog.pg_attribute a
		where 
			a.attrelid = o.oid 
			and a.attnum > 0
			and not a.attisdropped
	) - d.described_column_count as undescribed_column_count
from 
	pg_catalog.pg_class o
join pg_catalog.pg_namespace s 
	on s.oid = o.relnamespace  
left join lateral (
	select 
		max(d.description) filter (where d.objsubid = 0) as description 
		, count(1) filter (where d.objsubid > 0) as described_column_count
	from 
		pg_catalog.pg_description d 
	where 
		d.objoid = o.oid
		and d.classoid = 'pg_class'::regclass
) d 
	on true	
where 
	o.relkind = any(array['r', 'p', 'v', 'm']::char[])
	and s.nspname not similar to 'pg\_%|information_schema|public'
union all 
select 
	'routine' as obj_type
	, s.nspname as schema_name
	, o.proname as obj_name
	, d.description 
	, (d.description is null) as is_undescribed
	, null::integer as undescribed_column_count
from 
	pg_catalog.pg_proc o
join pg_catalog.pg_namespace s 
	on s.oid = o.pronamespace  
left join pg_catalog.pg_description d 
	on d.objoid = o.oid
	and d.classoid = 'pg_proc'::regclass
where 
	s.nspname not similar to 'pg\_%|information_schema|public'
;

comment on view v_sys_undescribed_obj is 'Неописанные объекты базы данных';
