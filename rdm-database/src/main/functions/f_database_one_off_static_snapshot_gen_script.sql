drop function if exists 
	f_database_one_off_static_snapshot_gen_script(
		text
	)
;

drop function if exists 
	f_database_one_off_static_snapshot_gen_script(
		text
		, boolean
	)
;

drop function if exists 
	f_database_one_off_static_snapshot_gen_script(
		text
		, boolean
		, boolean
		, text
	)
;

drop function if exists 
	f_database_one_off_static_snapshot_gen_script(
		name[]
		, boolean
		, boolean
		, text 
	)
;

drop function if exists 
	f_database_one_off_static_snapshot_gen_script(
		name[]
		, boolean
		, boolean
		, integer
		, text 
	)
;

drop function if exists 
	f_database_one_off_static_snapshot_gen_script(
		name[]
		, boolean
		, boolean
		, daterange
		, integer
		, text 
	)
;

drop function if exists 
	f_database_one_off_static_snapshot_gen_script(
		name[]
		, boolean
		, boolean
		, text
		, integer
		, text 
	) 
;

create or replace function 
	f_database_one_off_static_snapshot_gen_script(
		i_schemas name[] = null
		, i_include_tables boolean = false
		, i_include_data boolean = true
		, i_include_indices boolean = true
		, i_date_range_filter text = null
		, i_enforced_compatibility_level integer = null
		, i_alternative_quote_delimiter text = '$quote_delimiter$' 
	)
returns 
	setof text
language sql
stable
as $function$
-- Получение специального снимка базы данных минимального размера, 
-- в котором максимально устраняется динамическая составляющая. 
-- Такой снимок позволяет разворачивать БД на слабом сервере и без наличия
-- внешних объектов, от которых есть зависимости в текущей БД, если к ним есть прямая привязка. 
-- Представления конвертируются в таблицы. Функции остаются как есть, при этом
-- зависимости функций от представлений неявно замещаются зависимостями от 
-- получаемых таблиц с такими же именами.
-- Опционально, из состава целевых объектов БД могут быть исключены таблицы, как неинтерфейсные объекты. 
with
	selected_routine as (
		select
			v.id
		from 
			${mainSchemaName}.v_meta_view v
		where 
			v.is_routine
			and not v.is_external 
			and not v.is_disabled 
			and v.is_view_exists
			and (v.schema_name = any(i_schemas) or i_schemas is null)
	)
	, target_routine as (
		select
			v.id
			, v.view_oid as obj_id
			, v.obj_class
			, v.schema_name
			, v.internal_name
			, v.is_materialized as is_materialized_view
			, row_number()
				over(
					order by 
						v.creation_order
						, v.previously_defined_dependency_level
				) as obj_num
		from 
			${mainSchemaName}.v_meta_view v
		where 
			v.id in (
				select 
					id
				from 
					selected_routine
				union 
				select 
					v.id
				from 
					selected_routine r
				join ${mainSchemaName}.meta_view_dependency dep 
					on dep.view_id = r.id
				join ${mainSchemaName}.v_meta_view v
					on v.id = dep.master_view_id
					and v.is_routine
					and v.is_view_exists
			)	
	)
	, target_view as (
		select 
			v.view_oid as obj_id
			, v.schema_name
			, v.internal_name 
			, v.date_range_filter_condition
		from 
			${mainSchemaName}.v_meta_view v
		where 
			not v.is_routine
			and not v.is_external 
			and not v.is_disabled 
			and v.is_view_exists
			and (v.schema_name = any(i_schemas) or i_schemas is null)
		union 
		select distinct on (
				v.view_oid
			) 
			v.view_oid as obj_id
			, v.schema_name
			, v.internal_name
			, v.date_range_filter_condition
		from 
			target_routine r
		join ${mainSchemaName}.meta_view_dependency dep 
			on dep.view_id = r.id
		join ${mainSchemaName}.v_meta_view v
			on v.id = dep.master_view_id
			and not v.is_routine
			and v.is_view_exists
	)
	, target_table as (
		select 
			t.table_oid as obj_id
			, t.schema_name
			, t.internal_name 
			, t.internal_name as entity_name
			, t.date_range_filter_condition
		from 	
			${mainSchemaName}.v_meta_type t
		where 
			i_include_tables
			and t.is_table_exists
			and (t.schema_name = any(i_schemas) or i_schemas is null)
		union all
		select 
			t.localization_table_oid as obj_id
			, t.schema_name
			, t.localization_table_name as internal_name
			, t.internal_name as entity_name
			, t.lc_table_date_range_filter_condition as date_range_filter_condition
		from 	
			${mainSchemaName}.v_meta_type t
		where
			i_include_tables
			and t.is_localization_table_exists
			and (t.schema_name = any(i_schemas) or i_schemas is null)
		union
		select distinct on (
				master_table.obj_id
			)
			master_table.obj_id
			, master_table.schema_name
			, master_table.internal_name 
			, master_table.entity_name
			, master_table.date_range_filter_condition
		from 
			target_routine r
		join ${mainSchemaName}.meta_view_dependency dep 
			on dep.view_id = r.id
		join ${mainSchemaName}.v_meta_type t
			on t.id = dep.master_type_id
			and t.is_table_exists
		join lateral (
			values
				(
					t.table_oid
					, t.schema_name
					, t.internal_name
					, t.internal_name
					, t.date_range_filter_condition
				)
				, (
					t.localization_table_oid
					, t.schema_name
					, t.localization_table_name
					, t.internal_name
					, t.lc_table_date_range_filter_condition
				)
		) as master_table(
			obj_id
			, schema_name
			, internal_name
			, entity_name
			, date_range_filter_condition
		)
			on master_table.obj_id is not null
		where 
			not r.is_materialized_view
	)
	, target_schema as (
		select distinct 
			schema_name
		from 
			target_table
		union 
		select  
			schema_name
		from 
			target_view	
		union 
		select  
			schema_name
		from 
			target_routine
	)
select 
	case 
		when t.command_type = 'select'
		then 
			E'SELECT\n'
			|| case 
				when t.is_alternative_quote_delimiter_used 
				then i_alternative_quote_delimiter 
				else 'E''' 
			end
			|| t.command 
			|| case 
				when t.is_statement
				then ';'
				else ''
			end
			|| case 
				when t.is_intercmd_newline_delimiter_used
				then 
					case 
						when not t.is_alternative_quote_delimiter_used 
						then '\n' 
						else E'\n' 
					end
				else ''
			end
			|| case when t.is_alternative_quote_delimiter_used then i_alternative_quote_delimiter else '''' end
		else 
			t.command
	end 
	|| ';' as command
from (
	select 
		'SET standard_conforming_strings = on' as command
		, 'select' as command_type
		, 0 as obj_type_num
		, 0 as obj_num
		, 0 as command_num
		, true as is_statement
		, false as is_alternative_quote_delimiter_used
		, true as is_intercmd_newline_delimiter_used
	union all	
	select 
		format('DROP SCHEMA IF EXISTS %I CASCADE', schema_name)
		, 'select'
		, 1 as obj_type_num
		, 0 as obj_num
		, 0 as command_num
		, true as is_statement
		, false as is_alternative_quote_delimiter_used
		, true as is_intercmd_newline_delimiter_used
	from 
		target_schema
	union all	
	select 
		format('CREATE SCHEMA %I', schema_name)
		, 'select'
		, 2 as obj_type_num
		, 0 as obj_num
		, 0 as command_num
		, true as is_statement
		, false as is_alternative_quote_delimiter_used
		, true as is_intercmd_newline_delimiter_used
	from 
		target_schema
	union all
	select 
		c.command
		, c.command_type
		, 3 as obj_type_num
		, t.obj_num
		, c.command_num
		, c.is_statement
		, c.is_alternative_quote_delimiter_used
		, c.is_intercmd_newline_delimiter_used
	from (
		select
			t.schema_name
			, t.table_name
			, format(
				E'CREATE TABLE %I.%I (\n%s\n)'
				, t.schema_name
				, t.table_name
				, t.columns_def
			) as dest_table_def
			, format(
				'COPY %I.%I (%s) FROM stdin'
				, t.schema_name
				, t.table_name
				, t.columns_list
			) as copy_from_stdin_cmd
			, case 
				when t.is_view 
					or (
						i_date_range_filter is not null
						and t.date_range_filter_condition is not null
					)
				then 
					format(
						'COPY (SELECT %s FROM %I.%I%s) TO stdout'
						, t.columns_list
						, t.schema_name
						, t.table_name
						, case 
							when i_date_range_filter is not null
								and t.date_range_filter_condition is not null
							then 
								' WHERE '
								|| replace(
									replace(
										t.date_range_filter_condition
										, '{{date_range}}'
										, case i_date_range_filter
											when 'current report year' then (
												select 
													format(
														'[%s,%s)'
														, reference_date.value
														, (reference_date.value + interval '1 year')::date 
													) as date_range
												from (
													values(
														date_trunc('year', (date_trunc('month', current_date) - '1 month'::interval))::date
													) 
												) as reference_date(value)
											)
											else i_date_range_filter 
										end
									)
									, '{{entity_table}}'
									, t.schema_name || '.' || t.entity_name
								)
						end
					)
				else 
					format(
						'COPY %I.%I (%s) TO stdout'
						, t.schema_name
						, t.table_name
						, t.columns_list
					)
			end as copy_to_stdout_cmd
			, t.indices_def
			, row_number() over() as obj_num
		from (
			select 
				t.schema_name
				, t.table_name
				, t.entity_name
				, t.is_view
				, t.date_range_filter_condition
				, t.indices_def
				, array_to_string(
					array_agg(
						t.column_name
						order by t.attnum
					), 
					', '
				) as columns_list
				, array_to_string(
					array_agg(
						E'\t' || t.column_name || ' ' || t.column_type || ' ' || t.column_nullable
						order by t.attnum
					), 
					E',\n'
				) as columns_def
			from (
				select
					t.schema_name
					, t.internal_name as table_name
					, t.entity_name
					, t.is_view
					, t.date_range_filter_condition
					, indices.def as indices_def
					, a.attname as column_name
					, pg_catalog.format_type(a.atttypid, a.atttypmod) as column_type
					, case
						when a.attnotnull
						then 'not null'
						else 'null'
					end as column_nullable
					, a.attnum
				from (
					select 
						obj_id
						, schema_name
						, internal_name
						, entity_name
						, false as is_view
						, date_range_filter_condition
					from 
						target_table
					union all
					select
						obj_id
						, schema_name
						, internal_name
						, internal_name as entity_name
						, true as is_view
						, date_range_filter_condition
					from 
						target_view	
				) t 
				left join lateral (
					select 
						string_agg(
							replace(
								i.indexdef
								, ' ON ONLY '
								, ' ON '
							)
							, E';\n'
						) as def
					from 
						pg_catalog.pg_indexes i
					where
						i.schemaname = t.schema_name
						and i.tablename = t.internal_name
				) indices
					on true
				join pg_catalog.pg_attribute a 
					on a.attrelid = t.obj_id
					and a.attnum > 0
					and a.attisdropped = false
			) t
			group by
				t.schema_name
				, t.table_name
				, t.entity_name
				, t.is_view
				, t.date_range_filter_condition
				, t.indices_def
		) t
	) t
	join lateral (
		values
			(t.dest_table_def, 'select', 1, true, false, true)
			, (t.copy_from_stdin_cmd, 'select', 2, true, false, false)		
			, (t.copy_to_stdout_cmd, 'perform', 3, true, false, false)
			, ('\\.', 'select', 4, false, false, true) -- data_end_marker
			, (t.indices_def, 'select', 5, true, true, true)
	) 
	as c(
		command
		, command_type
		, command_num
		, is_statement
		, is_alternative_quote_delimiter_used
		, is_intercmd_newline_delimiter_used
	)
		on c.command_num = 1
		or (
			c.command_num = 5
			and i_include_indices
		)
		or (
			c.command_num in (2, 3, 4)
			and i_include_data
		)
	union all 
	select 
		${mainSchemaName}.f_sys_obj_definition(
			i_obj_class => r.obj_class
			, i_obj_id => r.obj_id
			, i_include_owner => false
			, i_enforced_compatibility_level => i_enforced_compatibility_level
		) as command
		, 'select' command_type
		, 5 as obj_type_num
		, r.obj_num
		, 0 as command_num
		, true as is_statement
		, true as is_alternative_quote_delimiter_used
		, true as is_intercmd_newline_delimiter_used
	from 
		target_routine r 
) t
order by 
	t.obj_type_num
	, t.obj_num
	, t.command_num	
$function$
;	

comment on function 
	f_database_one_off_static_snapshot_gen_script(
		name[]
		, boolean
		, boolean
		, boolean
		, text
		, integer
		, text 
	) 
	is 'Скрипт генерации одноразового статического снимка базы данных'
;
