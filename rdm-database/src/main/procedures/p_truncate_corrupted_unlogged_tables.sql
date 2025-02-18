create or replace procedure ${stagingSchemaName}.p_truncate_corrupted_unlogged_tables(
	i_schema_name name
)
language plpgsql
as $procedure$
declare 
	l_table_rec record;
begin
	for l_table_rec in (
		select
			t.schema_name
			, t.table_name
			, format(
				'select from %I.%I'
				, t.schema_name
				, t.table_name
			) as check_cmd
			, format(
				'truncate %I.%I'
				, t.schema_name
				, t.table_name
			) as truncate_cmd
		from 
			${mainSchemaName}.v_sys_table_size t
		where 
			t.schema_name = i_schema_name
		order by 
			table_name
	) loop

		-- check and truncate corrupted table
		begin
			execute 
				l_table_rec.check_cmd
			;
		exception
			-- Class 58 — System Error (errors external to PostgreSQL itself)
			-- 58P01 - undefined_file
			when sqlstate '58P01' then
				execute 
					l_table_rec.truncate_cmd
				;
				raise notice 
					'%.% table truncated'
					, l_table_rec.schema_name
					, l_table_rec.table_name
				;
		end
		;	
		
	end loop
	;
end
$procedure$
;			