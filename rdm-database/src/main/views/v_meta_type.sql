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
		from
			${mainSchemaName}.v_meta_attribute a
		group by 
			a.master_id
	)
select
	t.id
	, t.internal_name
	, ${mainSchemaName}.f_meta_type_dependency_level(
		i_meta_type_id => t.id
	) as dependency_level
	, t.schema_id
	, coalesce(s.internal_name, '${mainSchemaName}') as schema_name
	, case when target_schema.nspname = s.internal_name then true else false end as is_schema_exists
	, case when target_table.oid is not null then true else false end as is_table_exists
	, 'pk_' || t.internal_name as pk_index_name
	, case when pk_index.indexname is not null then true else false end as is_pk_index_exists			
	, case when pk_constraint.constraint_name is not null then true else false end as is_pk_constraint_exists
	, t.is_temporal
	, case 
		when target_table.oid is not null
			and not exists (
				select 
					1
				from
					pg_catalog.pg_attribute target_column
				where 
					target_column.attrelid = target_table.oid
					and target_column.attname = 'version'
			)
		then true
		else false
	end as is_target_table_non_temporal
	, ${mainSchemaName}.f_is_meta_type_has_localization(
		i_meta_type_id => t.id 
	) as is_localization_table_generated
	, t.internal_name || '_lc' as localization_table_name
	, case when lc_table.oid is not null then true else false end as is_localization_table_exists
	, t.master_type_id
	, master_type.internal_name as master_type_name
	, case 
		when exists (
				select 
					1
				from
					pg_catalog.pg_attribute target_column
				where 
					target_column.attrelid = target_table.oid
					and target_column.attname = 'master_id'
			)
		then true
		else false
	end as is_ref_to_master_column_exists
	, '${stagingSchemaName}' as staging_schema_name
	, ${mainSchemaName}.f_is_meta_type_has_attribute(
		i_meta_type_id => t.id
		, i_attribute_name => 'data_package_id'
	) as is_staging_table_generated
	, case when staging_table.oid is not null then true else false end as is_staging_table_exists
	, a.non_localisable_attributes
	, a.insert_expr_on_conflict_update_part
	, a.localisable_attributes
	, a.insert_expr_on_conflict_update_part_for_localisable
	, a.localisable_attr_values_list
	, case 
		when exists (
				select 
					1
				from
					pg_catalog.pg_attribute target_column
				where 
					target_column.attrelid = staging_table.oid
					and target_column.attname = 'master_id'
			)
		then true
		else false
	end as is_ref_to_master_column_in_staging_table_exists
	, t.is_built
	, type_name.lc_string as table_description
	, target_table_descr.description as target_table_description
	, staging_table_descr.description as staging_table_description
	, lc_table_descr.description as localization_table_description
from 
	${mainSchemaName}.meta_type t
left join ${mainSchemaName}.meta_schema s
	on s.id = t.schema_id
left join pg_catalog.pg_namespace target_schema
	on target_schema.nspname = coalesce(s.internal_name, '${mainSchemaName}')
left join pg_catalog.pg_class target_table
	on target_table.relnamespace = target_schema.oid 
	and target_table.relname = t.internal_name
	and target_table.relkind in ('r'::"char", 'p'::"char")
left join pg_catalog.pg_indexes pk_index
	on pk_index.schemaname = target_schema.nspname
	and pk_index.tablename = t.internal_name
	and pk_index.indexname = 'pk_' || t.internal_name
left join information_schema.table_constraints pk_constraint 
	on pk_constraint.table_schema = target_schema.nspname
	and pk_constraint.table_name = t.internal_name
	and pk_constraint.constraint_type = 'PRIMARY KEY'
left join ${mainSchemaName}.meta_type master_type
	on master_type.id = t.master_type_id
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
left join attributes a on a.master_id = t.id
where 
	t.is_primitive = false
	and t.is_abstract = false
;

comment on view v_meta_type is 'Метатипы';
