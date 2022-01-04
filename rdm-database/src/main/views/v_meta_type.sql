create or replace view v_meta_type
as
select
	t.id,
	t.internal_name,
	${database.defaultSchemaName}.f_meta_type_dependency_level(
		i_meta_type_id => t.id
	) as dependency_level,
	case when target_table.table_name is not null then true else false end as is_table_exists,
	'pk_' || t.internal_name as pk_index_name,
	case when pk_index.indexname is not null then true else false end as is_pk_index_exists,			
	case when pk_constraint.constraint_name is not null then true else false end as is_pk_constraint_exists,
	t.is_temporal,
	case 
		when target_table.table_name is not null
			and not exists (
				select 
					1
				from
					information_schema.columns target_column
				where
					target_column.table_schema = '${database.defaultSchemaName}'
					and target_column.table_name = t.internal_name
					and target_column.column_name = 'version'
			)
		then true
		else false
	end as is_target_table_non_temporal,
	${database.defaultSchemaName}.f_is_meta_type_has_localization(
		i_meta_type_id => t.id 
	) as is_localization_table_generated,
	t.internal_name || '_lc' as localization_table_name,
	case when lc_table.table_name is not null then true else false end as is_localization_table_exists
from 
	${database.defaultSchemaName}.meta_type t
left join 
	information_schema.tables target_table 
	on target_table.table_schema = '${database.defaultSchemaName}'
	and target_table.table_name = t.internal_name
	and target_table.table_type = 'BASE TABLE'
left join pg_catalog.pg_indexes pk_index	
	on pk_index.schemaname = '${database.defaultSchemaName}'
	and pk_index.tablename = t.internal_name
	and pk_index.indexname = 'pk_' || t.internal_name
left join 
	information_schema.table_constraints pk_constraint 
	on pk_constraint.table_schema = '${database.defaultSchemaName}'
	and pk_constraint.table_name = t.internal_name
	and pk_constraint.constraint_type = 'PRIMARY KEY'
left join 
	information_schema.tables lc_table 
	on lc_table.table_schema = '${database.defaultSchemaName}'
	and lc_table.table_name = t.internal_name || '_lc'
	and lc_table.table_type = 'BASE TABLE'
where 
	t.is_primitive = false
	and t.is_abstract = false
;