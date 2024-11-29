drop procedure if exists p_adjust_serial_sequence_value(
	name
	, name
	, name
	, name
	, name
);

create or replace procedure p_adjust_serial_sequence_value(
	i_schema_name name
	, i_table_name name
	, i_column_name name
	, i_sequence_name name = null
	, i_foreign_server name = null
	, i_allow_value_decreasing boolean = true
)
language plpgsql
security definer
as $procedure$
declare 
	l_sql_expr text;
begin
	l_sql_expr :=
		format($plpgsql$
			do $$
			declare	
				l_sequence_name text := 
					nullif('%s', '')
				;
				l_sql_expr text;
			begin
				if l_sequence_name is null then
					l_sequence_name := 
						pg_catalog.pg_get_serial_sequence('%I.%I', '%s')
					;
				else
					if l_sequence_name !~ '^[[:alnum:]]+\.[[:alnum:]]+$' then 
						l_sequence_name :=  
							'%s.%s'
						;
					end if
					;
				end if
				;
			
			 	if l_sequence_name is null then
			 		raise exception 
			 			'Cannot find sequence for the table column specified: %s.%s.%s'
					;			 			
			 	end if
			 	;
			 	
			 	l_sql_expr := 
					format($sql$
						select 
							setval('%%s', t.max_id)					
						from (
							select 
								coalesce((select last_value from %%s), 0) as sequence_last_value
								, coalesce(max(%s), 0) as max_id
							from 
								%I.%I
						) t
						where 
							(
								t.sequence_last_value < t.max_id
								or (t.sequence_last_value > t.max_id and %L::boolean)
							)
							and t.max_id >= (
								select 
									min_value
								from
									pg_catalog.pg_sequences
								where 
									schemaname = '%I'
									and sequencename = '%%I'													
							)
						$sql$
						, l_sequence_name
						, l_sequence_name
						, l_sequence_name
					);
			 	
				execute l_sql_expr;
			end
			$$;
			$plpgsql$
			, i_sequence_name 
			, i_schema_name
			, i_table_name
			, i_column_name
			, i_schema_name
			, i_sequence_name 
			, i_schema_name
			, i_table_name
			, i_column_name
			, i_column_name
			, i_schema_name
			, i_table_name
			, i_allow_value_decreasing
			, i_schema_name
		);
	 
	if i_foreign_server is null then 
		execute l_sql_expr;
	else 
		execute '
			select 1
			from 
				${dbms_extension.dblink.schema}.dblink(
					$1::text
					, $script$' || l_sql_expr || '$script$
				) as t(result text)
			'
			using i_foreign_server
			;
	end if; 
end
$procedure$;		

comment on procedure p_adjust_serial_sequence_value(
	name
	, name
	, name
	, name
	, name
	, boolean
) is 'Исправление текущего значения последовательности';
