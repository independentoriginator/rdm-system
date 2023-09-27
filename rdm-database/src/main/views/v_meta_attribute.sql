create or replace view v_meta_attribute
as
with recursive 
	attr as (
		select 
			a.id
			, t.id AS descendant_type_id
			, t.super_type_id
			, t.id as meta_type_id
			, t.is_temporal
			, a.internal_name
			, a.attr_type_id 
			, a.length
			, a.precision
			, a.scale
			, a.is_non_nullable
			, a.is_unique
			, a.is_localisable
			, a.fk_on_delete_cascade
			, a.ordinal_position
			, a.default_value
		from 
			${mainSchemaName}.meta_type t
		left join ${mainSchemaName}.meta_attribute a on a.master_id = t.id
		union all
		select 
			0 as id
			, t.id AS descendant_type_id
			, t.super_type_id
			, t.id as meta_type_id
			, t.is_temporal
			, 'master_id'::varchar(63) as internal_name
			, t.master_type_id as attr_type_id 
			, null as length
			, null as precision
			, null as scale
			, case 
				when t.id = t.master_type_id then false
				else true
			end as is_non_nullable
			, false as is_unique
			, false as is_localisable
			, true as fk_on_delete_cascade
			, 0 as ordinal_position
			, null as default_value
		from 
			${mainSchemaName}.meta_type t
		where 
			t.master_type_id is not null
		union all
		select 
			a_inherited.id
			, a.descendant_type_id
			, t.super_type_id
			, a_inherited.master_id as meta_type_id
			, a.is_temporal
			, a_inherited.internal_name
			, case 
				when a_inherited.attr_type_id = a_inherited.master_id 
				then a.descendant_type_id
				else a_inherited.attr_type_id 
			end as attr_type_id
			, a_inherited.length
			, a_inherited.precision
			, a_inherited.scale 
			, a_inherited.is_non_nullable
			, a_inherited.is_unique 
			, a_inherited.is_localisable
			, a_inherited.fk_on_delete_cascade
			, a_inherited.ordinal_position
			, a_inherited.default_value
		from (
			select distinct 
				super_type_id 
				, descendant_type_id
				, is_temporal
			from 
				attr 
		) a
		join ${mainSchemaName}.meta_attribute a_inherited
			on a_inherited.master_id = a.super_type_id
		join ${mainSchemaName}.meta_type t 
			on t.id = a_inherited.master_id
		where 
			not a_inherited.is_owned_by_temporal_type
			or a.is_temporal   
	)
select 
	a.id
	, a.master_id
	, a.meta_type_name
	, a.schema_name 
	, a.internal_name
	, a.target_attr_type
	, a.ordinal_position
	, (target_column.column_name is not null) as is_column_exists
	, ${mainSchemaName}.f_column_type_specification(
		i_data_type => target_column.data_type
		, i_character_maximum_length => target_column.character_maximum_length
		, i_numeric_precision => target_column.numeric_precision
		, i_numeric_scale => target_column.numeric_scale	
		, i_datetime_precision => target_column.datetime_precision	
	) as column_data_type
	, a.attr_type_name
	, a.is_fk_constraint_added
	, a.fk_constraint_name
	, (fk_constraint.conname is not null) as is_fk_constraint_exists
	, a.index_name
	, (fk_index.indexname is not null) as is_fk_index_exists
	, a.is_referenced_type_temporal
	, a.version_ref_name
	, (a.is_fk_constraint_added and a.is_referenced_type_temporal) as is_chk_constraint_added
	, a.check_constraint_name
	, case 
		when a.is_fk_constraint_added and a.is_referenced_type_temporal then
			format(
				'check (((%s is null) = (%s is null)))'
				, a.internal_name
				, a.version_ref_name
			)		
	end as check_constraint_expr
	, (chk_constraint.conname is not null) as is_check_constraint_exists
	, pg_catalog.pg_get_constraintdef(chk_constraint.oid) as target_check_constraint_expr
	, a.is_non_nullable
	, (target_column.is_nullable = 'NO') as is_notnull_constraint_exists
	, a.is_unique
	, a.unique_constraint_name
	, (u_constraint.constraint_name is not null) as is_unique_constraint_exists
	, a.default_value
	, target_column.column_default
	, a.is_localisable
	, a.staging_schema_name
	, (target_staging_table_column.column_name is not null) as is_staging_table_column_exists
	, ${mainSchemaName}.f_column_type_specification(
		i_data_type => target_staging_table_column.data_type
		, i_character_maximum_length => target_staging_table_column.character_maximum_length
		, i_numeric_precision => target_staging_table_column.numeric_precision
		, i_numeric_scale => target_staging_table_column.numeric_scale	
		, i_datetime_precision => target_staging_table_column.datetime_precision	
	) as staging_table_column_data_type
	, (target_staging_table_column.is_nullable = 'NO') as is_staging_table_column_notnull_constraint_exists
	, target_staging_table_column.column_default as staging_table_column_default
	, a.attr_type_schema 
	, a.ancestor_type_id
	, attr_name.lc_string as column_description
	, target_column_descr.description target_column_description
	, target_staging_table_column_descr.description staging_column_description
	, a.fk_on_delete_cascade
	, (fk_constraint.confdeltype = 'f'::"char") as target_fk_on_delete_cascade 
from (
	select
		a.id
		, t.id as master_id
		, t.internal_name as meta_type_name
		, coalesce(s.internal_name, '${mainSchemaName}') as schema_name 
		, a.internal_name
		, case attr_type.internal_name
			when 's' 
				then 
					case when a.length is not null 
						then 'character varying(' || a.length::text || ')' 
						else 'text'
					end
			when 'n' 
				then 'numeric' ||
					case when a.precision is not null 
						then '(' || a.precision::text || ', ' || coalesce(a.scale, 0)::text || ')' 
						else ''
					end
			when 'd' 
				then case when a.precision is not null 
					then 'timestamp (' || a.precision::text || ') without time zone' 
					else 'date'
				end
			when 'b' then 'boolean'
			else '${type.id}'
		end as target_attr_type
		, a.ordinal_position
		, attr_type.internal_name as attr_type_name
		, case when attr_type.is_primitive = false then true else false end as is_fk_constraint_added
		, substring('fk_' || t.internal_name || '$' || a.internal_name, 1, ${stagingSchemaName}.f_system_name_max_length()) as fk_constraint_name
		, a.fk_on_delete_cascade
		, substring('i_' || t.internal_name || '$' || a.internal_name, 1, ${stagingSchemaName}.f_system_name_max_length()) as index_name
		, attr_type.is_temporal as is_referenced_type_temporal
		, regexp_replace(a.internal_name, '_id$', '') || '_version' as version_ref_name
		, substring('chk_' || t.internal_name || '$' || a.internal_name, 1, ${stagingSchemaName}.f_system_name_max_length()) as check_constraint_name
		, a.is_non_nullable
		, a.is_unique
		, substring('uc_' || t.internal_name || '$' || a.internal_name, 1, ${stagingSchemaName}.f_system_name_max_length()) as unique_constraint_name
		, def_val_expr.expr_text as default_value
		, a.is_localisable
		, '${stagingSchemaName}' as staging_schema_name
		, coalesce(attr_type_schema.internal_name, '${mainSchemaName}') as attr_type_schema 
		, a.meta_type_id as ancestor_type_id
	from 
		attr a
	join 
		${mainSchemaName}.meta_type t
		on t.id = a.descendant_type_id				
	join 
		${mainSchemaName}.meta_type attr_type
		on attr_type.id = a.attr_type_id
	left join ${mainSchemaName}.meta_schema attr_type_schema
		on attr_type_schema.id = attr_type.schema_id
	left join ${mainSchemaName}.meta_schema s
		on s.id = t.schema_id
	left join
		${mainSchemaName}.meta_expr_body def_val_expr
		on def_val_expr.master_id = a.default_value
		and def_val_expr.dbms_type_id = (
			select 
				id
			from
				${mainSchemaName}.dbms_type
			where
				code = 'postgresql'
		)
	where
		a.id is not null
) a	
left join pg_catalog.pg_namespace target_schema
	on target_schema.nspname = a.schema_name
left join pg_catalog.pg_class target_table
	on target_table.relnamespace = target_schema.oid 
	and target_table.relname = a.meta_type_name
	and target_table.relkind in ('r'::"char", 'p'::"char")
join ${mainSchemaName}.meta_type meta_attribute
	on meta_attribute.internal_name = 'meta_attribute' 
left join ${mainSchemaName}.meta_attribute name_attr
	on name_attr.master_id = meta_attribute.id
	and name_attr.internal_name = 'name'
left join ${mainSchemaName}.meta_attribute_lc attr_name
	on attr_name.master_id = a.id
	and attr_name.attr_id = name_attr.id
	and attr_name.lang_id = ${mainSchemaName}.f_default_language_id()
	and attr_name.is_default_value = true
left join information_schema.columns target_column
	on target_column.table_schema = target_schema.nspname
	and target_column.table_name = a.meta_type_name
	and target_column.column_name = a.internal_name
left join pg_catalog.pg_description target_column_descr
	on target_column_descr.objoid = target_table.oid
	and target_column_descr.classoid = 'pg_class'::regclass
	and target_column_descr.objsubid = target_column.ordinal_position
left join pg_catalog.pg_constraint fk_constraint
	on fk_constraint.conrelid = target_table.oid
	and fk_constraint.conname = a.fk_constraint_name
	and fk_constraint.contype = 'f'::"char" 
left join pg_catalog.pg_indexes fk_index	
	on fk_index.schemaname = target_schema.nspname
	and fk_index.tablename = a.meta_type_name
	and fk_index.indexname = a.index_name
left join information_schema.table_constraints u_constraint 
	on u_constraint.table_schema = target_schema.nspname
	and u_constraint.table_name = a.meta_type_name
	and u_constraint.constraint_name = a.unique_constraint_name
	and u_constraint.constraint_type = 'UNIQUE'
left join pg_catalog.pg_constraint chk_constraint
	on chk_constraint.conrelid = target_table.oid
	and chk_constraint.conname = a.check_constraint_name
	and chk_constraint.contype = 'c'::"char" 
left join pg_catalog.pg_namespace staging_schema
	on staging_schema.nspname = a.staging_schema_name
left join pg_catalog.pg_class staging_table
	on staging_table.relnamespace = staging_schema.oid 
	and staging_table.relname = a.meta_type_name
	and staging_table.relkind in ('r'::"char", 'p'::"char")
left join information_schema.columns target_staging_table_column
	on target_staging_table_column.table_schema = a.staging_schema_name
	and target_staging_table_column.table_name = a.meta_type_name
	and target_staging_table_column.column_name = a.internal_name
left join pg_catalog.pg_description target_staging_table_column_descr
	on target_staging_table_column_descr.objoid = staging_table.oid
	and target_staging_table_column_descr.classoid = 'pg_class'::regclass
	and target_staging_table_column_descr.objsubid = target_staging_table_column.ordinal_position
;

comment on view v_meta_attribute is 'Метаатрибуты';
