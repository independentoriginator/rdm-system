create or replace view v_meta_index
as
with recursive 
	type_index as (
		select 
			i.id
	        , t.id as descendant_type_id
	        , t.super_type_id
	        , t.schema_id
	        , t.is_temporal
			, i.tag
			, i.is_unique 
			, i.is_constraint_used
			, i.is_constraint_deferrable
		from 
			${mainSchemaName}.meta_type t
		left join ${mainSchemaName}.meta_index i on i.master_id = t.id 
		union all
		select 
			i_inherited.id
	        , i.descendant_type_id
	        , t.super_type_id
	        , t.schema_id
	        , i.is_temporal
			, i_inherited.tag
			, i_inherited.is_unique
			, i_inherited.is_constraint_used
			, i_inherited.is_constraint_deferrable
		from (
			select distinct 
				descendant_type_id
				, super_type_id
				, is_temporal
			from 
				type_index 
		) i
		join ${mainSchemaName}.meta_type t 
			on t.id = i.super_type_id
		left join ${mainSchemaName}.meta_index i_inherited
			on i_inherited.master_id = t.id 
	)
	, meta_index as (
		select
			i.id
			, i.master_id
			, i.meta_type_name
			, i.schema_name
			, i.index_name
			, i.index_columns
			, i.is_temporal
			, i.is_unique
			, i.is_constraint_used
			, i.is_constraint_deferrable
			, i.constraint_name
			, (target_index.oid is not null) as is_target_index_exists
			, (target_constraint.oid is not null) as is_target_constraint_exists
			, pg_index.indisunique as is_target_index_unique
			, (target_constraint.contype = 'u'::"char") as is_target_constraint_unique
			, target_constraint.condeferrable as is_target_constraint_deferrable
			, pg_index_col.index_columns as target_index_columns
			, pg_constraint_col.constraint_columns as target_constraint_columns
		from (
			select
				i.id
				, t.id as master_id
				, t.is_temporal
				, t.internal_name as meta_type_name
				, coalesce(s.internal_name, '${mainSchemaName}') as schema_name
				, i.is_unique
				, i.is_constraint_used
				, i.is_constraint_deferrable
				, substring(
					case when i.is_unique then 'u' else '' end
					|| 'i_'
					|| t.internal_name 
					|| '$' 
					|| i.tag
					, 1
					, ${mainSchemaName}.f_system_name_max_length()
				) as index_name
				, substring(
					case when i.is_unique then 'u' else '' end
					|| 'c_'
					|| t.internal_name 
					|| '$' 
					|| i.tag
					, 1
					, ${mainSchemaName}.f_system_name_max_length()
				) as constraint_name
				, ic.index_columns
				|| case 
					when t.is_temporal then 
						', valid_to'
					else 
						''
				end as index_columns
			from 
				type_index i
			join ${mainSchemaName}.meta_type t
				on t.id = i.descendant_type_id	
			left join ${mainSchemaName}.meta_schema s
				on s.id = t.schema_id
			join lateral (
				select 
					string_agg(
						ic.meta_attr_name
						, ', ' order by ic.ordinal_position
					) as index_columns
				from
					${mainSchemaName}.meta_index_column ic
				join ${mainSchemaName}.meta_index mi 
					on mi.id = ic.master_id
				left join ${mainSchemaName}.meta_attribute a
					on a.master_id = mi.master_id
					and a.internal_name = ic.meta_attr_name
				where
					ic.master_id = i.id
					and (
						t.is_temporal
						or (
							not a.is_owned_by_temporal_type
							and ic.meta_attr_name != any(array['version', 'valid_from', 'valid_to'])
						)
						or ic.meta_attr_name = 'master_id'
					) 
			) ic 
				on true
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
		) pg_index_col 
			on true
		left join pg_catalog.pg_constraint target_constraint
			on target_constraint.conrelid = target_table.oid
			and target_constraint.conname = i.constraint_name
			and target_constraint.contype = 'u'::"char" 
		left join lateral (
			select 
				string_agg(a.attname, ', ' order by array_position(target_constraint.conkey, a.attnum)) as constraint_columns
			from 
				pg_catalog.pg_attribute a
			where
				a.attrelid = target_constraint.conrelid
				and a.attnum = any(target_constraint.conkey)
		) pg_constraint_col 
			on true
		where 
			i.id is not null
			and i.index_columns is not null
	)
	, fk_index as (
		select 
			a.master_id
			, a.index_name
		from 
			${mainSchemaName}.v_meta_attribute a
		where 
			a.is_fk_constraint_added			
	)
	, uc_index as (
		select 
			a.master_id
			, a.unique_constraint_name as index_name
		from 
			${mainSchemaName}.v_meta_attribute a
		where 
			a.is_unique			
	)
select 
	i.id
	, i.master_id
	, i.meta_type_name
	, i.schema_name
	, i.index_name
	, i.index_columns
	, i.is_target_index_exists
	, i.is_unique
	, i.is_target_index_unique
	, i.target_index_columns
	, i.is_constraint_used
	, i.is_constraint_deferrable
	, i.constraint_name
	, i.is_target_constraint_exists
	, i.is_target_constraint_unique
	, i.is_target_constraint_deferrable
	, i.target_constraint_columns
from 
	meta_index i
union all 
select
	null as id
	, t.id as master_id
	, t.internal_name as meta_type_name
	, n.nspname::varchar as schema_name
	, target_index.relname as index_name
	, pg_index_col.index_columns
	, (pg_index.indexrelid is not null) as is_target_index_exists
	, pg_index.indisunique as is_unique
	, pg_index.indisunique as is_target_index_unique
	, pg_index_col.index_columns as target_index_columns
	, null as is_constraint_used
	, null as is_constraint_deferrable
	, null as constraint_name
	, null as is_target_constraint_exists
	, null as is_target_constraint_unique
	, null as is_target_constraint_deferrable
	, null as target_constraint_columns
from 
	${mainSchemaName}.meta_type t
left join ${mainSchemaName}.meta_schema s
	on s.id = t.schema_id
join pg_catalog.pg_namespace n
	on n.nspname = coalesce(s.internal_name, '${mainSchemaName}')
join pg_catalog.pg_class target_table 
	on target_table.relnamespace = n.oid
	and target_table.relname = t.internal_name
left join information_schema.table_constraints pk_constraint 
	on pk_constraint.table_schema = n.nspname
	and pk_constraint.table_name = t.internal_name
	and pk_constraint.constraint_type = 'PRIMARY KEY'
join pg_catalog.pg_index pg_index	
	on pg_index.indrelid = target_table.oid 
join pg_catalog.pg_class target_index
	on target_index.oid = pg_index.indexrelid
	and (target_index.relname <> pk_constraint.constraint_name or pk_constraint.constraint_name is null)
	and (target_index.relname <> 'uc_' || t.internal_name || '$id_valid_to' or t.is_temporal = false) -- implicit index for the unique constraint
left join lateral (
	select 
		string_agg(a.attname, ', ' order by array_position(pg_index.indkey, a.attnum)) as index_columns
	from 
		pg_catalog.pg_attribute a
	where
		a.attrelid = pg_index.indrelid
		and a.attnum = any(pg_index.indkey)
) pg_index_col 
	on true
where 
	(t.internal_name not like 'meta\_%' or n.nspname <> '${mainSchemaName}') 
	and not exists (
		select 
			1
		from 
			meta_index
		where 
			meta_index.master_id = t.id
			and meta_index.index_name = target_index.relname
	)
	and not exists (
		select 
			1
		from 
			fk_index
		where 
			fk_index.master_id = t.id
			and fk_index.index_name = target_index.relname
	)
	and not exists (
		select 
			1
		from 
			uc_index
		where 
			uc_index.master_id = t.id
			and uc_index.index_name = target_index.relname
	)
	and not exists (
		select 
			1
		from 
			meta_index
		where 
			meta_index.master_id = t.id
			and meta_index.constraint_name = target_index.relname
			and meta_index.is_unique
			and meta_index.is_constraint_used
	)
union all 
select
	null as id
	, t.id as master_id
	, t.internal_name as meta_type_name
	, n.nspname::varchar as schema_name
	, target_constraint.conname as index_name
	, pg_constraint_col.constraint_columns as index_columns
	, null as is_target_index_exists
	, (target_constraint.contype = 'u'::"char") as is_unique
	, null as is_target_index_unique
	, null as target_index_columns
	, null as is_constraint_used
	, null as is_constraint_deferrable
	, target_constraint.conname as constraint_name
	, (target_constraint.oid is not null) as is_target_constraint_exists
	, (target_constraint.contype = 'u'::"char") as is_target_constraint_unique
	, target_constraint.condeferrable as is_target_constraint_deferrable
	, pg_constraint_col.constraint_columns as target_constraint_columns
from 
	${mainSchemaName}.meta_type t
left join ${mainSchemaName}.meta_schema s
	on s.id = t.schema_id
join pg_catalog.pg_namespace n
	on n.nspname = coalesce(s.internal_name, '${mainSchemaName}')
join pg_catalog.pg_class target_table 
	on target_table.relnamespace = n.oid
	and target_table.relname = t.internal_name
left join information_schema.table_constraints pk_constraint 
	on pk_constraint.table_schema = n.nspname
	and pk_constraint.table_name = t.internal_name
	and pk_constraint.constraint_type = 'PRIMARY KEY'
join pg_catalog.pg_constraint target_constraint
	on target_constraint.conrelid = target_table.oid
	and target_constraint.contype = 'u'::"char"
	and (target_constraint.conname <> pk_constraint.constraint_name or pk_constraint.constraint_name is null)
	and (target_constraint.conname <> 'uc_' || t.internal_name || '$id_valid_to' or t.is_temporal = false) -- implicit index for the unique constraint
left join lateral (
	select 
		string_agg(a.attname, ', ' order by array_position(target_constraint.conkey, a.attnum)) as constraint_columns
	from 
		pg_catalog.pg_attribute a
	where
		a.attrelid = target_constraint.conrelid
		and a.attnum = any(target_constraint.conkey)
) pg_constraint_col 
	on true
where 
	(t.internal_name not like 'meta\_%' or n.nspname <> '${mainSchemaName}') 
	and not exists (
		select 
			1
		from 
			meta_index
		where 
			meta_index.master_id = t.id
			and meta_index.constraint_name = target_constraint.conname
	)
	and not exists (
		select 
			1
		from 
			uc_index
		where 
			uc_index.master_id = t.id
			and uc_index.index_name = target_constraint.conname
	)
;

comment on view v_meta_index is 'Метаиндексы';
