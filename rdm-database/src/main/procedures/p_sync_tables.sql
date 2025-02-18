create or replace procedure 
	p_sync_tables(
		i_source_table_schema name
		, i_source_table_name name
		, i_target_table_schema name
		, i_target_table_name name
		, i_sync_data boolean = true
	)
language plpgsql
as $procedure$
declare 
	l_rec record;
begin
	<<tables>>
	for l_rec in (
		with 
			table_spec as (
				select 
					c.oid as table_id
					, c.relname as table_name
					, n.nspname as schema_name
					, c.relkind as table_kind
					, d.description
				from 
					pg_catalog.pg_namespace n
				join pg_catalog.pg_class c
					on c.relnamespace = n.oid
					and c.relkind = any(array['r', 'p']::char[])	
				left join pg_catalog.pg_description d 
					on d.objoid = c.oid
					and d.classoid = 'pg_class'::regclass
					and d.objsubid = 0
			)
			, column_spec as (
				select 
					a.attrelid as table_id
					, a.attname as column_name
					, pg_catalog.format_type(a.atttypid, a.atttypmod) as column_type			
					, a.attnotnull as is_not_null			
					, a_descr.description
				from 
					pg_catalog.pg_attribute a
				left join pg_catalog.pg_description a_descr
					on a_descr.objoid = a.attrelid
					and a_descr.classoid = 'pg_class'::regclass
					and a_descr.objsubid = a.attnum
				where 
					not a.attisdropped			
			)
		select
			ddl.sttmnt
		from 
			table_spec source_table
		join column_spec source_table_column
			on source_table_column.table_id = source_table.table_id
		left join table_spec target_table
			on target_table.schema_name = i_target_table_schema
			and target_table.table_name = i_target_table_name
		left join column_spec target_table_column
			on target_table_column.table_id = target_table.table_id
			and target_table_column.column_name = source_table_column.column_name
		join lateral(
			values 
				(
					case 
						when target_table.table_id is null then
							format(
								'create table %I.%I as %I.%I with %sdata'
								, i_target_table_schema
								, i_target_table_name
								, i_source_table_schema
								, i_source_table_name
								, case when not i_sync_data then 'no ' else '' end								
							)
					end 
				)
				, (
					case 
						when nullif(source_table.description, target_table.description) is not null then
							format(
								'comment on table %I.%I is $comment$%s$comment$'
								, i_target_table_schema
								, i_target_table_name
								, source_table.description								
							)
					end 
				)
				, (
					case 
						when target_table_column.column_name is null then
							format(
								'alter table %I.%I add column %I %s %s'
								, i_target_table_schema
								, i_target_table_name
								, source_table_column.column_name
								, source_table_column.column_type		
								, case when source_table_column.is_not_null then 'not null' else 'null' end
							)
						when target_table_column.column_type <> source_table_column.column_type then
							format(
								E'call ${mainSchemaName}.p_alter_table_column_type('
								'\n	i_schema_name => %L'
								'\n	, i_table_name => %L'
								'\n	, i_column_name => %L'
								'\n	, i_column_type => %L'
								'\n)'
								, i_target_table_schema
								, i_target_table_name
								, source_table_column.column_name
								, source_table_column.column_type		
							)
					end 
				)
				, (
					case 
						when nullif(source_table_column.description, target_table_column.description) is not null then
							format(
								'comment on column %I.%I.%I is $comment$%s$comment$'
								, i_target_table_schema
								, i_target_table_name
								, target_table_column.column_name
								, source_table_column.description								
							)
					end 
				)
		) ddl(sttmnt)
			on ddl.sttmnt is not null
		where 
			source_table.schema_name = i_source_table_schema
			and source_table.table_name = i_source_table_name
	)
	loop
		execute
			l_rec.sttmnt
		;		
	end loop tables
	;	
end
$procedure$
;		

comment on procedure 
	p_sync_tables(
		name
		, name
		, name
		, name
		, boolean
	) 
	is 'Синхронизировать таблицы'
;
