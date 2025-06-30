drop procedure if exists
	p_sync_tables(
		name
		, name
		, name
		, name
		, boolean
	)
;

drop procedure if exists
	p_sync_tables(
		name
		, name
		, name
		, name
		, boolean
		, boolean
	)
;

drop procedure if exists
	p_recreate_table_as(
		name
		, name
		, text
		, text
		, text
	)
;

create or replace procedure 
	p_recreate_table_as(
		i_table_schema name
		, i_table_name name
		, i_query text
		, i_partitioning_strategy text = null
		, i_partition_key text = null
		, i_forcibly_recreate boolean = false
	)
language plpgsql
security definer
as $procedure$
declare 
	l_temp_table_name name := 
		format(
			'%I_%I'
			, i_table_schema
			, i_table_name
		)
	;
	l_temp_name_tmpl name := 'p_recreate_table_as_temp_%s';
	l_rec record;
begin
	-- temporary table as a sample of the target structure
	execute
		format('
			drop table if exists %I;
			create temp table %I as %s with no data;
			'
			, l_temp_table_name
			, l_temp_table_name
			, i_query
		)
	;
	
	<<ddl_commands>>
	for l_rec in (
		with 
			table_spec as (
				select 
					t.table_id
					, t.table_name
					, t.schema_id
					, t.schema_name
					, t.partitioning_strategy
					, t.partition_key
					, format(
						l_temp_name_tmpl
						, t.table_id
					)::name as temp_name
				from (			
					select 
						c.oid as table_id
						, c.relname as table_name
						, c.relnamespace as schema_id
						, n.nspname as schema_name
						, null::text as partitioning_strategy
						, null::text as partition_key
					from 
						pg_catalog.pg_namespace n
					join pg_catalog.pg_class c
						on c.relnamespace = n.oid
						and c.relkind = 'r'::"char"	
					union all
					select 
						t.table_id
						, t.table_name
						, t.schema_id
						, t.schema_name
						, t.partitioning_strategy
						, t.partition_key
					from 
						${mainSchemaName}.v_sys_partitioned_table t
				) t
			)
			, column_spec as (
				select 
					a.attrelid as table_id
					, a.attname as column_name
					, pg_catalog.format_type(a.atttypid, a.atttypmod) as column_type
					, a.attnum as column_position
				from 
					pg_catalog.pg_attribute a
				where 
					not a.attisdropped			
					and a.attnum > 0
			)
			, column_matching as (
				select
					target_table_column.column_name as old_column_name
					, target_table_column.column_type as old_column_type
					, target_table_column.column_position as old_column_position
					, temp_table_column.column_name as new_column_name
					, temp_table_column.column_type as new_column_type			
					, temp_table_column.column_position as new_column_position
				from (
					select 
						c.column_name
						, c.column_type		
						, c.column_position
					from 
						table_spec t
					join column_spec c
						on c.table_id = t.table_id
					where 
						t.schema_id = pg_my_temp_schema()
						and t.table_name = l_temp_table_name			
				) temp_table_column
				full join (
					select 
						c.column_name
						, c.column_type		
						, c.column_position
					from 
						table_spec t
					join column_spec c
						on c.table_id = t.table_id
					where 
						t.schema_name = i_table_schema
						and t.table_name = i_table_name
				) target_table_column
					on target_table_column.column_name = temp_table_column.column_name
			)
		select 
			ddl.sttmnt
		from 
			table_spec temp_table
		left join table_spec target_table
			on target_table.schema_name = i_table_schema
			and target_table.table_name = i_table_name
		join lateral (
			select 
				string_agg(
					format(
						'create table %I.%I partition of %I.%I %s'
						, p.partition_schema_name
						, coalesce(p.partition_temp_name, p.partition_table_name)
						, i_table_schema
						, target_table.temp_name
						, p.partition_expression
					)
					, E';\n'
				) filter (
					where
						p.is_new
						and p.partition_expression is not null
				) as new_partition_creation_commands
				, string_agg(
					format(
						'insert into %I.%I(%s) select %s from %I.%I'
						, i_table_schema
						, target_table.temp_name
						, transition_columns.columns
						, transition_columns.columns
						, p.partition_schema_name
						, p.partition_table_name
					)
					, E';\n'
				) filter (
					where 
						p.is_old
						and p.partition_table_name is not null
				) as data_copy_commands
				, string_agg(
					format(
						'alter table %I.%I rename to %I'
						, p.partition_schema_name
						, p.partition_temp_name
						, p.partition_table_name
					)
					, E';\n'
				) filter (
					where 
						p.is_new
						and p.partition_temp_name is not null
				) as partition_rename_commands
			from (
				select
					p.partition_schema_name
					, p.partition_table_name
					, case 
						when p.partition_table_id is not null then
							format(
								l_temp_name_tmpl
								, p.partition_table_id
							)
					end::name as partition_temp_name
					, p.partition_expression
					, p.is_old
					, p.is_new
				from
					${mainSchemaName}.f_table_partitions(
						i_table_id => target_table.table_id
						, i_partitioning_strategy => i_partitioning_strategy
						, i_partition_key => i_partition_key
					) p
				union all
				select 
					target_table.schema_name as partition_schema_name
					, target_table.table_name as partition_table_name
					, null as partition_temp_name
					, null as partition_expression
					, true as is_old
					, (i_partitioning_strategy is null) as is_new
				where 
					target_table.partitioning_strategy is null
			) p
			join lateral (
				select 
					string_agg(old_table_column.column_name, ', ') as columns
				from 
					column_spec old_table_column
				join column_spec new_table_column
					on new_table_column.table_id = target_table.table_id
					and new_table_column.column_name = old_table_column.column_name 
				where
					old_table_column.table_id = temp_table.table_id
			) transition_columns
				on true
		) partitions
			on true
		join lateral(
			values (
				case 
					when target_table.table_id is null
					then
						format(
							'create table %I.%I(like %I.%I)%s'
							, i_table_schema
							, i_table_name
							, temp_table.schema_name
							, temp_table.table_name
							, case 
								when i_partitioning_strategy is not null then
									format(
										' partition by %s(%s)'
										, i_partitioning_strategy
										, i_partition_key 
									)
								else 
									''
							end
						)
				end 
			)
			, (
				case 
					when target_table.table_id is not null
						and (
							nullif(i_partition_key, target_table.partition_key) is not null
							or (i_partition_key is null and target_table.partition_key is not null)
							or nullif(i_partitioning_strategy, target_table.partitioning_strategy) is not null
							or (i_partitioning_strategy is null and target_table.partitioning_strategy is not null)
							or exists (
								select 
									1
								from 
									column_matching m 
								where 
									m.old_column_name = m.new_column_name
									and m.old_column_position <> m.new_column_position
							)
							or i_forcibly_recreate
						)
					then
						concat_ws(
							E';\n'
							-- create new table with a temporary name
							, format(
								'create table %I.%I(like %I.%I)%s'
								, i_table_schema
								, target_table.temp_name 
								, temp_table.schema_name
								, temp_table.table_name
								, case 
									when i_partitioning_strategy is not null then
										format(
											' partition by %s(%s)'
											, i_partitioning_strategy
											, i_partition_key 
										)
									else 
										''
								end
							)
							-- create new partitions
							, partitions.new_partition_creation_commands
							-- copy existing data
							, partitions.data_copy_commands
							-- drop old table
							, format(
								'drop table %I.%I'
								, i_table_schema
								, i_table_name
							)
							-- rename newly created partitions
							, partitions.partition_rename_commands
							-- rename newly created table
							, format(
								'alter table %I.%I rename to %I'
								, i_table_schema
								, target_table.temp_name
								, i_table_name
							)
						)
				end 
			)
		) ddl(
			sttmnt
		)
			on ddl.sttmnt is not null
		where 
			temp_table.schema_id = pg_my_temp_schema()
			and temp_table.table_name = l_temp_table_name			
		union all
		(
			select 
				ddl.sttmnt
			from 
				column_matching t
			join table_spec target_table
				on target_table.schema_name = i_table_schema
				and target_table.table_name = i_table_name
			join lateral(
				values (
					case 
						when t.old_column_name is null 
							and t.new_column_name is not null
						then
							format(
								'alter table %I.%I add column %I %s null'
								, i_table_schema
								, i_table_name
								, t.new_column_name
								, t.new_column_type
							)
						when t.old_column_name = t.new_column_name
							and t.old_column_type <> t.new_column_type
						then
							format(
								E'do $$'
								'\nbegin'
								'\n	call'
								'\n		${mainSchemaName}.p_alter_table_column_type('
								'\n			i_schema_name => %L'
								'\n			, i_table_name => %L'
								'\n			, i_column_name => %L'
								'\n			, i_column_type => %L'
								'\n			, i_defer_dependent_obj_recreation => true'
								'\n		)'
								'\n	;'
								'\nend'
								'\n$$'
								'\n;'	
								, i_table_schema
								, i_table_name
								, t.new_column_name
								, t.new_column_type
							)
						when t.old_column_name is not null 
							and t.new_column_name is null
						then
							format(
								'alter table %I.%I drop column %I'
								, i_table_schema
								, i_table_name
								, t.old_column_name
							)
					end 
				)
			) ddl(
				sttmnt
			)
				on ddl.sttmnt is not null
			where 
				not exists (
					select 
						1
					from 
						column_matching m 
					where 
						m.old_column_name = m.new_column_name
						and m.old_column_position <> m.new_column_position
				)
				and not i_forcibly_recreate
			order by 
				new_column_position
		)
	)
	loop
		raise notice
			'%'
			, l_rec.sttmnt
		;
		execute
			l_rec.sttmnt
		;		
	end loop ddl_commands
	;	

	-- drop the temporary table
	execute
		format('
			drop table %I
			'
			, l_temp_table_name
		)
	;

exception
	-- Class 42 — Syntax Error or Access Rule Violation
	-- 42846 cannot_coerce
	when sqlstate '42846' then
		call
			${mainSchemaName}.p_recreate_table_as(
				i_table_schema => i_table_schema
				, i_table_name => i_table_name
				, i_query => i_query
				, i_partitioning_strategy => i_partitioning_strategy
				, i_partition_key => i_partition_key
				, i_forcibly_recreate => true
			)
		;
end
$procedure$
;		

comment on procedure 
	p_recreate_table_as(
		name
		, name
		, text
		, text
		, text
		, boolean
	) 
	is 'Пересоздать таблицу на основе запроса'
;
