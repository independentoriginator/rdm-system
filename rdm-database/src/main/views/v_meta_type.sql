create or replace view v_meta_type
as
select
	t.id
	, t.internal_name
	, ${database.defaultSchemaName}.f_meta_type_dependency_level(
		i_meta_type_id => t.id
	) as dependency_level
	, t.schema_id
	, coalesce(s.internal_name, '${database.defaultSchemaName}') as schema_name
	, case when target_schema.schema_name is not null and target_schema.schema_name = s.internal_name then true else false end as is_schema_exists
	, case when target_table.table_name is not null then true else false end as is_table_exists
	, 'pk_' || t.internal_name as pk_index_name
	, case when pk_index.indexname is not null then true else false end as is_pk_index_exists			
	, case when pk_constraint.constraint_name is not null then true else false end as is_pk_constraint_exists
	, t.is_temporal
	, case 
		when target_table.table_name is not null
			and not exists (
				select 
					1
				from
					information_schema.columns target_column
				where
					target_column.table_schema = target_schema.schema_name
					and target_column.table_name = t.internal_name
					and target_column.column_name = 'version'
			)
		then true
		else false
	end as is_target_table_non_temporal
	, ${database.defaultSchemaName}.f_is_meta_type_has_localization(
		i_meta_type_id => t.id 
	) as is_localization_table_generated
	, t.internal_name || '_lc' as localization_table_name
	, case when lc_table.table_name is not null then true else false end as is_localization_table_exists
	, t.master_type_id
	, master_type.internal_name as master_type_name
	, case 
		when exists (
				select 
					1
				from
					information_schema.columns target_column
				where
					target_column.table_schema = target_schema.schema_name
					and target_column.table_name = t.internal_name
					and target_column.column_name = 'master_id'
			)
		then true
		else false
	end as is_ref_to_master_column_exists
	, '${stagingSchemaName}' as staging_schema_name
	, case 
		when exists (
				select 
					1
				from
					${database.defaultSchemaName}.v_meta_attribute a
				where
					a.master_id = t.id
					and a.internal_name = 'data_package_id'
			)
		then true
		else false
	end as is_staging_table_generated
	, case when staging_table.table_name is not null then true else false end as is_staging_table_exists
	, a.non_localisable_attributes
	, a.insert_expr_on_conflict_update_part
	, a.localisable_attributes
	, a.insert_expr_on_conflict_update_part_for_localisable
	, a.localisable_attr_values_list
from 
	${database.defaultSchemaName}.meta_type t
left join ${database.defaultSchemaName}.meta_schema s
	on s.id = t.schema_id
left join information_schema.schemata target_schema
	on target_schema.schema_name = coalesce(s.internal_name, '${database.defaultSchemaName}')
left join information_schema.tables target_table 
	on target_table.table_schema = target_schema.schema_name
	and target_table.table_name = t.internal_name
	and target_table.table_type = 'BASE TABLE'
left join pg_catalog.pg_indexes pk_index	
	on pk_index.schemaname = target_schema.schema_name
	and pk_index.tablename = t.internal_name
	and pk_index.indexname = 'pk_' || t.internal_name
left join information_schema.table_constraints pk_constraint 
	on pk_constraint.table_schema = target_schema.schema_name
	and pk_constraint.table_name = t.internal_name
	and pk_constraint.constraint_type = 'PRIMARY KEY'
left join ${database.defaultSchemaName}.meta_type master_type
	on master_type.id = t.master_type_id
left join information_schema.tables lc_table 
	on lc_table.table_schema = target_schema.schema_name
	and lc_table.table_name = t.internal_name || '_lc'
	and lc_table.table_type = 'BASE TABLE'
left join information_schema.tables staging_table 
	on staging_table.table_schema = '${stagingSchemaName}'
	and staging_table.table_name = t.internal_name
	and staging_table.table_type = 'BASE TABLE'
join lateral (
	select 
		string_agg(
			case 
				when a.is_localisable = false 
				then a.internal_name
			end
			, ', ' order by a.ordinal_position nulls last
		) as non_localisable_attributes
		, string_agg(
			case 
				when a.is_localisable = true
				then a.internal_name
			end
			, ', ' order by a.ordinal_position nulls last
		) as localisable_attributes
		, string_agg(
			case 
				when a.is_localisable = false 
				then a.internal_name || ' = excluded.' || a.internal_name
			end
			, ', ' order by a.ordinal_position nulls last
		) as insert_expr_on_conflict_update_part		
		, string_agg(
			case 
				when a.is_localisable = true
				then a.internal_name || ' = excluded.' || a.internal_name
			end
			, ', ' order by a.ordinal_position nulls last
		) as insert_expr_on_conflict_update_part_for_localisable
		, string_agg(
			case 
				when a.is_localisable = true
				then '(''' || a.internal_name || ''', t.' || a.internal_name || ')'
			end
			, ', ' order by a.ordinal_position nulls last
		) as localisable_attr_values_list
	from
		${database.defaultSchemaName}.v_meta_attribute a
	where
		a.master_id = t.id
) a on true
where 
	t.is_primitive = false
	and t.is_abstract = false
;