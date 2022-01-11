create or replace view v_meta_attribute
as
with recursive attr as (
	select 
		a.id,
        t.id AS descendant_type_id,
        t.super_type_id,
        t.id as meta_type_id,
		a.internal_name,
		a.attr_type_id, 
		a.length, 
		a.precision, 
		a.scale, 
		a.is_non_nullable, 
		a.is_unique, 
		a.is_localisable, 
		a.ordinal_position,
		a.default_value
	from 
		${database.defaultSchemaName}.meta_type t
	left join ${database.defaultSchemaName}.meta_attribute a on a.master_id = t.id 
	union all
	select 
		a_inherited.id,
        a.descendant_type_id,
        t.super_type_id,
		a_inherited.master_id as meta_type_id,
		a_inherited.internal_name,
		case when a_inherited.attr_type_id = a_inherited.master_id 
			then a.descendant_type_id
			else a_inherited.attr_type_id 
		end as attr_type_id,
		a_inherited.length, 
		a_inherited.precision, 
		a_inherited.scale, 
		a_inherited.is_non_nullable, 
		a_inherited.is_unique, 
		a_inherited.is_localisable, 
		a_inherited.ordinal_position,
		a_inherited.default_value
	from 
		attr a
	join ${database.defaultSchemaName}.meta_attribute a_inherited
		on a_inherited.master_id = a.super_type_id
	join ${database.defaultSchemaName}.meta_type t 
		on t.id = a_inherited.master_id
)
select
	a.id,
	t.id as master_id,
	t.internal_name as meta_type_name,
	coalesce(s.internal_name, '${database.defaultSchemaName}') as schema_name, 
	a.internal_name,
	case attr_type.internal_name
		when 's' 
			then 'character varying' ||
				case when a.length is not null 
					then '(' || a.length::text || ')' 
					else ''
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
		else 'bigint'
	end as target_attr_type,
	a.ordinal_position,
	case when target_column.column_name is not null then true else false end as is_column_exists,
	case target_column.data_type
		when 'character varying' 
			then target_column.data_type ||
				case when target_column.character_maximum_length is not null
					then '(' || target_column.character_maximum_length || ')'
					else ''
				end
		when 'numeric' 
			then target_column.data_type ||
				case when target_column.numeric_precision is not null
					then '(' || target_column.numeric_precision::text || ', ' || coalesce(target_column.numeric_scale, 0)::text || ')'
					else ''
				end
		when 'timestamp without time zone' 
			then 'timestamp (' || coalesce(target_column.datetime_precision, 6)::text || ') without time zone'
		else 
			target_column.data_type
	end as column_data_type,
	attr_type.internal_name as attr_type_name,
	case when attr_type.is_primitive = false then true else false end as is_fk_constraint_added,
	'fk_' || t.internal_name || '$' || a.internal_name as fk_constraint_name,
	case when fk_constraint.constraint_name is not null then true else false end as is_fk_constraint_exists,
	'i_' || t.internal_name || '$' || a.internal_name as index_name,
	case when fk_index.indexname is not null then true else false end as is_fk_index_exists,
	attr_type.is_temporal as is_referenced_type_temporal,
	regexp_replace(a.internal_name, '_id$', '') || '_version' as version_ref_name,
	a.is_non_nullable,
	case when target_column.is_nullable = 'NO' then true else false end as is_notnull_constraint_exists,
	a.is_unique,
	'uc_' || t.internal_name || '$' || a.internal_name as unique_constraint_name,
	case when u_constraint.constraint_name is not null then true else false end as is_unique_constraint_exists,
	'chk_' || t.internal_name || '$' || a.internal_name as check_constraint_name,
	def_val_expr.expr_text as default_value,
	target_column.column_default
from 
	attr a
join 
	${database.defaultSchemaName}.meta_type t
	on t.id = a.descendant_type_id				
join 
	${database.defaultSchemaName}.meta_type attr_type
	on attr_type.id = a.attr_type_id		
left join ${database.defaultSchemaName}.meta_schema s
	on s.id = t.schema_id
left join information_schema.schemata target_schema
	on target_schema.schema_name = coalesce(s.internal_name, '${database.defaultSchemaName}')
left join 
	information_schema.columns target_column
	on target_column.table_schema = target_schema.schema_name
	and target_column.table_name = t.internal_name
	and target_column.column_name = a.internal_name
left join 
	information_schema.table_constraints fk_constraint 
	on fk_constraint.table_schema = target_schema.schema_name
	and fk_constraint.table_name = t.internal_name
	and fk_constraint.constraint_name = 'fk_' || t.internal_name || '$' || a.internal_name
	and fk_constraint.constraint_type = 'FOREIGN KEY'
left join pg_catalog.pg_indexes fk_index	
	on fk_index.schemaname = target_schema.schema_name
	and fk_index.tablename = t.internal_name
	and fk_index.indexname = 'i_' || t.internal_name || '$' || a.internal_name
left join 
	information_schema.table_constraints u_constraint 
	on u_constraint.table_schema = target_schema.schema_name
	and u_constraint.table_name = t.internal_name
	and u_constraint.constraint_name = 'uc_' || t.internal_name || '$' || a.internal_name
	and u_constraint.constraint_type = 'UNIQUE'
left join
	${database.defaultSchemaName}.meta_expr_body def_val_expr
	on def_val_expr.master_id = a.default_value
	and def_val_expr.dbms_type_id = (
		select 
			id
		from
			${database.defaultSchemaName}.dbms_type
		where
			code = 'postgresql'
	)
where 
	a.id is not null
	and a.is_localisable = false
;