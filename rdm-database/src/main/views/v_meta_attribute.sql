create or replace view v_meta_attribute
as
with recursive attr as (
	select 
		a.id
        , t.id AS descendant_type_id
        , t.super_type_id
        , t.id as meta_type_id
		, a.internal_name
		, a.attr_type_id 
		, a.length
		, a.precision
		, a.scale
		, a.is_non_nullable
		, a.is_unique
		, a.is_localisable
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
		, 'master_id'::varchar(63) as internal_name
		, t.master_type_id as attr_type_id 
		, null as length
		, null as precision
		, null as scale
		, true as is_non_nullable
		, false as is_unique
		, false as is_localisable
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
		, a_inherited.internal_name
		, case when a_inherited.attr_type_id = a_inherited.master_id 
			then a.descendant_type_id
			else a_inherited.attr_type_id 
		end as attr_type_id
		, a_inherited.length
		, a_inherited.precision
		, a_inherited.scale 
		, a_inherited.is_non_nullable
		, a_inherited.is_unique 
		, a_inherited.is_localisable
		, a_inherited.ordinal_position
		, a_inherited.default_value
	from (
		select distinct 
			super_type_id 
			, descendant_type_id 
		from 
			attr 
	) a
	join ${mainSchemaName}.meta_attribute a_inherited
		on a_inherited.master_id = a.super_type_id
	join ${mainSchemaName}.meta_type t 
		on t.id = a_inherited.master_id
)
select 
	a.id
	, a.master_id
	, a.meta_type_name
	, a.schema_name 
	, a.internal_name
	, a.target_attr_type
	, a.ordinal_position
	, case when target_column.column_name is not null then true else false end as is_column_exists
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
	, case when fk_constraint.constraint_name is not null then true else false end as is_fk_constraint_exists
	, a.index_name
	, case when fk_index.indexname is not null then true else false end as is_fk_index_exists
	, a.is_referenced_type_temporal
	, a.version_ref_name
	, a.is_non_nullable
	, case when target_column.is_nullable = 'NO' then true else false end as is_notnull_constraint_exists
	, a.is_unique
	, a.unique_constraint_name
	, case when u_constraint.constraint_name is not null then true else false end as is_unique_constraint_exists
	, a.check_constraint_name
	, a.default_value
	, target_column.column_default
	, a.is_localisable
	, a.staging_schema_name
	, case when target_staging_table_column.column_name is not null then true else false end as is_staging_table_column_exists
	, ${mainSchemaName}.f_column_type_specification(
		i_data_type => target_staging_table_column.data_type
		, i_character_maximum_length => target_staging_table_column.character_maximum_length
		, i_numeric_precision => target_staging_table_column.numeric_precision
		, i_numeric_scale => target_staging_table_column.numeric_scale	
		, i_datetime_precision => target_staging_table_column.datetime_precision	
	) as staging_table_column_data_type
	, case when target_staging_table_column.is_nullable = 'NO' then true else false end as is_staging_table_column_notnull_constraint_exists
	, target_staging_table_column.column_default as staging_table_column_default
	, a.attr_type_schema 
	, a.ancestor_type_id
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
		, substring('fk_' || t.internal_name || '$' || a.internal_name, 1, ${mainSchemaName}.f_system_name_max_length()) as fk_constraint_name
		, substring('i_' || t.internal_name || '$' || a.internal_name, 1, ${mainSchemaName}.f_system_name_max_length()) as index_name
		, attr_type.is_temporal as is_referenced_type_temporal
		, regexp_replace(a.internal_name, '_id$', '') || '_version' as version_ref_name
		, a.is_non_nullable
		, a.is_unique
		, substring('uc_' || t.internal_name || '$' || a.internal_name, 1, ${mainSchemaName}.f_system_name_max_length()) as unique_constraint_name
		, substring('chk_' || t.internal_name || '$' || a.internal_name, 1, ${mainSchemaName}.f_system_name_max_length()) as check_constraint_name
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
left join information_schema.schemata target_schema
	on target_schema.schema_name = a.schema_name
left join 
	information_schema.columns target_column
	on target_column.table_schema = target_schema.schema_name
	and target_column.table_name = a.meta_type_name
	and target_column.column_name = a.internal_name
left join 
	information_schema.table_constraints fk_constraint 
	on fk_constraint.table_schema = target_schema.schema_name
	and fk_constraint.table_name = a.meta_type_name
	and fk_constraint.constraint_name = a.fk_constraint_name
	and fk_constraint.constraint_type = 'FOREIGN KEY'
left join pg_catalog.pg_indexes fk_index	
	on fk_index.schemaname = target_schema.schema_name
	and fk_index.tablename = a.meta_type_name
	and fk_index.indexname = a.index_name
left join 
	information_schema.table_constraints u_constraint 
	on u_constraint.table_schema = target_schema.schema_name
	and u_constraint.table_name = a.meta_type_name
	and u_constraint.constraint_name = a.unique_constraint_name
	and u_constraint.constraint_type = 'UNIQUE'
left join 
	information_schema.columns target_staging_table_column
	on target_staging_table_column.table_schema = a.staging_schema_name
	and target_staging_table_column.table_name = a.meta_type_name
	and target_staging_table_column.column_name = a.internal_name
;