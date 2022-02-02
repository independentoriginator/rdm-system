create or replace view v_meta_index
as
with recursive type_index as (
	select 
		i.id
        , t.id AS descendant_type_id
        , t.super_type_id
        , t.schema_id
		, i.tag
		, i.is_unique 
	from 
		${database.defaultSchemaName}.meta_type t
	left join ${database.defaultSchemaName}.meta_index i on i.master_id = t.id 
	union all
	select 
		i_inherited.id
        , i.descendant_type_id
        , t.super_type_id
        , t.schema_id
		, i_inherited.tag
		, i_inherited.is_unique 
	from 
		type_index i
	join ${database.defaultSchemaName}.meta_index i_inherited
		on i_inherited.master_id = i.super_type_id
	join ${database.defaultSchemaName}.meta_type t 
		on t.id = i_inherited.master_id
)
select
	i.id
	, i.master_id
	, i.meta_type_name
	, i.schema_name
	, i.index_name
	, i.index_columns
	, case when target_index.oid is not null then true else false end as is_target_index_exists
	, i.is_unique
	, pg_index.indisunique as is_target_index_unique
	, pg_index_col.index_columns as target_index_columns
from (
	select
		i.id
		, t.id as master_id
		, t.internal_name as meta_type_name
		, coalesce(s.internal_name, '${database.defaultSchemaName}') as schema_name
		, i.is_unique
		, 'i_' || t.internal_name || '$' || i.tag as index_name
		, ic.index_columns || 
		case 
			when t.is_temporal then 
				', valid_to'
			else ''
		end as index_columns
	from 
		type_index i
	join 
		${database.defaultSchemaName}.meta_type t
		on t.id = i.descendant_type_id	
	left join ${database.defaultSchemaName}.meta_schema s
		on s.id = t.schema_id
	join lateral (
		select 
			string_agg(
				ic.meta_attr_name
				, ', ' order by ic.ordinal_position
			) as index_columns
		from
			${database.defaultSchemaName}.meta_index_column ic
		where
			ic.master_id = i.id
	) ic on true
) i
left join pg_catalog.pg_namespace n 
	on n.nspname = i.schema_name
left join pg_catalog.pg_class target_table 
	on target_table.relnamespace = n.oid
	and target_table.relname = i.meta_type_name
left join pg_catalog.pg_class target_index
	on target_index.relnamespace = target_table.relnamespace
	and target_index.relname = i.index_name
	and target_index.relkind = 'i'::"char"
left join pg_catalog.pg_index pg_index	
	on pg_index.indexrelid = target_index.oid
left join lateral (
	select 
		string_agg(a.attname, ', ' order by array_position(pg_index.indkey, a.attnum)) as index_columns
	from 
		pg_catalog.pg_attribute a
	where
		a.attrelid = pg_index.indrelid
		and a.attnum = any(pg_index.indkey)
) pg_index_col on true

;