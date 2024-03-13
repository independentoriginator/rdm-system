create or replace function f_apply_backward_compatibility_macro(
	i_program_code text
	, i_compatibility_level integer -- server major version 
)
returns text
language plpgsql
immutable
as $function$
declare 
	l_converted_program_code text := i_program_code;
	l_rec record;
begin
	-- Backward compatibility macro examples:
	 
		/* #if #server_major_version >= 11 */
		/* #then */
	--	rows between current row and unbounded following exclude current row /* #else */
		/* rows between 1 following and unbounded following */
		/* #endif */
		
		/* #if #server_major_version <= 10 */
		/* #then */
	--	rows between 1 following and unbounded following
		/* #else rows between current row and unbounded following exclude current row */
		/* #endif */
		
		/* #if #server_major_version < 11 */
		/* #then rows between 1 following and unbounded following */
		/* #else */
	--	rows between current row and unbounded following exclude current row
		/* #endif */
	
		/* #if #server_major_version >= 12 */
		/* #then */
	--	materialized
		/* #endif */
	
	--	/* #if #server_major_version >= 12 */ /* #then */materialized/* #endif */
	
	if i_compatibility_level is not null then
	
		for l_rec in (
			select 
				bc_macro
				, target_code_block
			from (
				select
					conditional_expr[1] as bc_macro 
					, case 
						when  
							case predicate_operator[1]
								when '>=' then left_operand_value >= predicate_right_operand[1]
								when '>' then left_operand_value > predicate_right_operand[1]
								when '=' then left_operand_value = predicate_right_operand[1]
								when '<' then left_operand_value < predicate_right_operand[1]
								when '<=' then left_operand_value <= predicate_right_operand[1]
							end
						then coalesce(then_expr[1], block_expr[1], '')
						else coalesce(else_expr[1], '')
					end as target_code_block
				from 
					regexp_matches(
						i_program_code
						, '(?:\/\*\s*#if\s*.+?\s*\/\*\s*#endif\s*\*\/){1,1}?' -- /* #if {predicate} */ ... /* #endif */  
						, 'g'
					) 
					as conditional_expr
				left join regexp_match(
						conditional_expr[1]
						, '#if\s*(.+?)\s*(?:\*\/\s*\/\*\s*\#then)+?'
					) as predicate 
						on true
				left join regexp_match(
						predicate[1]
						, '([^\=\>\<\s]+)\s*[\=\>\<]+.*'
					) as predicate_left_operand 
						on true
				left join regexp_match(
						predicate[1]
						, '.*\s*[\=\>\<]+\s*([^\=\>\<]+)'
					) as predicate_right_operand 
						on true		
				left join regexp_match(
						predicate[1]
						, '[^\=\>\<]+\s*([\=\>\<]*)\s*[^\=\>\<]+'
					) as predicate_operator 
						on true		
				left join replace(
						predicate_left_operand[1]
						, '#server_major_version'
						, i_compatibility_level::varchar
					) as left_operand_value
						on true
				left join regexp_match(
						conditional_expr[1]
						, '\#then\s*(?:\*\/)*\s*(.+?)\s*(?:\/\*\s*\#endif)'
					) as block_expr
						on true
				left join regexp_match(
						conditional_expr[1]
						, '\#then\s*(?:\*\/)*\s*(.+?)\s*(?:\*\/\s*)*?(?=\/\*\s*\#else)'
					) as then_expr
						on true
				left join regexp_match(
						block_expr[1]
						, '\#else\s*(?:\*\/)*\s*(?:\/\*)*\s*(.+?)\s*(?:\*\/\s*)*'
					) as else_expr
						on true
			) t 
			where 
				target_code_block is not null
		)
		loop
			l_converted_program_code := 
				replace(
					l_converted_program_code
					, l_rec.bc_macro
					, l_rec.target_code_block
				);		
		end loop;
	
	end if;

	return l_converted_program_code;
end
$function$;

comment on function f_apply_backward_compatibility_macro(
	text
	, integer 
) is 'Применить макрокоманды для обратной совместимости';
