create or replace view v_meta_type
as
with
	attributes as (
		select 
			a.master_id
			, string_agg(
				case 
					when a.is_localisable = false 
					then a.internal_name || 
						case 
							when a.is_referenced_type_temporal then
								', ' || a.version_ref_name
							else ''
						end					
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
						|| case
							when a.is_referenced_type_temporal then
								', ' || a.version_ref_name || ' = excluded.' || a.version_ref_name
							else 
								''
						end
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
			, string_agg(
				case 
					when a.is_localisable = true
					then 'when ''' || a.internal_name || ''' then t.' || a.internal_name
				end
				, ' ' order by a.ordinal_position nulls last
			) as localisable_attr_case_expr_body
		from
			${mainSchemaName}.v_meta_attribute a
		group by 
			a.master_id
	)
select
	t.id
	, t.internal_name
	, t.dependency_level
	, t.schema_id
	, t.schema_name
	, (target_schema.oid is not null) as is_schema_exists
	, (target_table.oid is not null) as is_table_exists
	, t.pk_index_name
	, (pk_index.indexname is not null) as is_pk_index_exists			
	, (pk_constraint.constraint_name is not null) as is_pk_constraint_exists
	, t.is_temporal
	, (
		target_table.oid is not null
		and not exists (
			select 
				1
			from
				pg_catalog.pg_attribute target_column
			where 
				target_column.attrelid = target_table.oid
				and target_column.attname = 'version'
		)
	) as is_target_table_non_temporal
	, t.is_localization_table_generated
	, t.localization_table_name
	, (lc_table.oid is not null) as is_localization_table_exists
	, t.master_type_id
	, t.master_type_name
	, (
		exists (
			select 
				1
			from
				pg_catalog.pg_attribute target_column
			where 
				target_column.attrelid = target_table.oid
				and target_column.attname = 'master_id'
		)
	) as is_ref_to_master_column_exists
	, t.staging_schema_name
	, t.is_staging_table_generated
	, (staging_table.oid is not null) as is_staging_table_exists
	, a.non_localisable_attributes
	, a.insert_expr_on_conflict_update_part
	, a.localisable_attributes
	, a.insert_expr_on_conflict_update_part_for_localisable
	, a.localisable_attr_values_list
	, (
		exists (
			select 
				1
			from
				pg_catalog.pg_attribute target_column
			where 
				target_column.attrelid = staging_table.oid
				and target_column.attname = 'master_id'
		)
	) as is_ref_to_master_column_in_staging_table_exists
	, t.is_built
	, t.table_description
	, target_table_descr.description as target_table_description
	, staging_table_descr.description as staging_table_description
	, lc_table_descr.description as localization_table_description
	, a.localisable_attr_case_expr_body
	, t.actual_rec_u_constraint_name
	, (actual_rec_u_constraint.constraint_name is not null) as is_actual_rec_u_constraint_exists
	, target_table.oid as table_oid
	, lc_table.oid as localization_table_oid
from (	
	select
		t.id
		, t.internal_name
		, ${mainSchemaName}.f_meta_type_dependency_level(
			i_meta_type_id => t.id
		) as dependency_level
		, t.schema_id
		, coalesce(s.internal_name, '${mainSchemaName}') as schema_name
		, 'pk_' || t.internal_name as pk_index_name
		, substring(
			'uc_' || t.internal_name || '$id_valid_to'
			, 1
			, ${stagingSchemaName}.f_system_name_max_length()
		) as actual_rec_u_constraint_name
		, t.is_temporal
		, ${mainSchemaName}.f_is_meta_type_has_localization(
			i_meta_type_id => t.id 
		) as is_localization_table_generated
		, t.internal_name || '_lc' as localization_table_name
		, t.master_type_id
		, master_type.internal_name as master_type_name
		, '${stagingSchemaName}' as staging_schema_name
		, ${mainSchemaName}.f_is_meta_type_has_attribute(
			i_meta_type_id => t.id
			, i_attribute_name => 'data_package_id'
		) as is_staging_table_generated
		, t.is_built
		, type_name.lc_string as table_description
	from 
		${mainSchemaName}.meta_type t
	left join ${mainSchemaName}.meta_schema s
		on s.id = t.schema_id
	left join ${mainSchemaName}.meta_type master_type
		on master_type.id = t.master_type_id
	join ${mainSchemaName}.meta_type meta_type
		on meta_type.internal_name = 'meta_type' 
	left join ${mainSchemaName}.meta_attribute name_attr
		on name_attr.master_id = meta_type.id
		and name_attr.internal_name = 'name'
	left join ${mainSchemaName}.meta_type_lc type_name
		on type_name.master_id = t.id
		and type_name.attr_id = name_attr.id
		and type_name.lang_id = ${mainSchemaName}.f_default_language_id()
		and type_name.is_default_value = true
	where 
		t.is_primitive = false
		and t.is_abstract = false
) t
left join pg_catalog.pg_namespace target_schema
	on target_schema.nspname = t.schema_name
left join pg_catalog.pg_class target_table
	on target_table.relnamespace = target_schema.oid 
	and target_table.relname = t.internal_name
	and target_table.relkind in ('r'::"char", 'p'::"char")
left join pg_catalog.pg_indexes pk_index
	on pk_index.schemaname = target_schema.nspname
	and pk_index.tablename = t.internal_name
	and pk_index.indexname = t.pk_index_name
left join information_schema.table_constraints pk_constraint 
	on pk_constraint.table_schema = target_schema.nspname
	and pk_constraint.table_name = t.internal_name
	and pk_constraint.constraint_type = 'PRIMARY KEY'
left join information_schema.table_constraints actual_rec_u_constraint 
	on actual_rec_u_constraint.table_schema = target_schema.nspname
	and actual_rec_u_constraint.table_name = t.internal_name
	and actual_rec_u_constraint.constraint_name = t.actual_rec_u_constraint_name
	and actual_rec_u_constraint.constraint_type = 'UNIQUE'
left join pg_catalog.pg_class lc_table
	on lc_table.relnamespace = target_schema.oid 
	and lc_table.relname = t.internal_name || '_lc'
	and lc_table.relkind in ('r'::"char", 'p'::"char")
left join pg_catalog.pg_namespace staging_schema
	on staging_schema.nspname = '${stagingSchemaName}'
left join pg_catalog.pg_class staging_table
	on staging_table.relnamespace = staging_schema.oid 
	and staging_table.relname = t.internal_name
	and staging_table.relkind in ('r'::"char", 'p'::"char")
left join pg_catalog.pg_description target_table_descr 
	on target_table_descr.objoid = target_table.oid
	and target_table_descr.classoid = 'pg_class'::regclass
	and target_table_descr.objsubid = 0
left join pg_catalog.pg_description lc_table_descr 
	on lc_table_descr.objoid = lc_table.oid
	and lc_table_descr.classoid = 'pg_class'::regclass
	and lc_table_descr.objsubid = 0	
left join pg_catalog.pg_description staging_table_descr 
	on staging_table_descr.objoid = staging_table.oid
	and staging_table_descr.classoid = 'pg_class'::regclass
	and staging_table_descr.objsubid = 0	
left join attributes a 
	on a.master_id = t.id
;

comment on view v_meta_type is 'Метатипы';
