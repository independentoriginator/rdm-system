drop function if exists 
	f_table_partitions(
		${type.system_object_id}
		, text
		, text
	)
;

create or replace function 
	f_table_partitions(
		i_table_id ${type.system_object_id}
		, i_partitioning_strategy text
		, i_partition_key text
	)
returns table (
	partition_table_id ${type.system_object_id}
	, partition_schema_name name
	, partition_table_name name
	, partition_expression text
	, is_old boolean
	, is_new boolean 
)
language plpgsql
as $function$
declare
	l_partitioned_table_rec record; 
begin
	select 
		pt.*
		, (c.column_name is not null) as is_partition_key_field_exists
	into 
		l_partitioned_table_rec
	from 
		${mainSchemaName}.v_sys_partitioned_table pt
	left join information_schema.columns c
		on c.table_schema = pt.schema_name
		and c.table_name = pt.table_name
		and c.column_name = i_partition_key		
	where 
		pt.table_id = i_table_id
	;

	if l_partitioned_table_rec.table_name is null then
		return
		;
	end if
	;

	if l_partitioned_table_rec.partitioning_strategy = i_partitioning_strategy
		and l_partitioned_table_rec.partition_key = i_partition_key
	then
		return query
			select
				p.partition_table_id
				, p.partition_schema_name
				, p.partition_table_name
				, p.partition_expression
				, true as is_old
				, true as is_new
			from
				${mainSchemaName}.v_sys_table_partition p
			where 
				p.table_id = i_table_id
		;
		return 
		;
	end if
	;

	return query
		select
			p.partition_table_id
			, p.partition_schema_name
			, p.partition_table_name
			, p.partition_expression
			, true as is_old
			, false as is_new
		from
			${mainSchemaName}.v_sys_table_partition p
		where 
			p.table_id = i_table_id
	;

	if l_partitioned_table_rec.is_partition_key_field_exists then
		return query 
			execute 
				format(
					$sql$
					select 
						null::${type.system_object_id} as partition_table_id
						, %L::name as partition_schema_name
						, format(
							'%I_%%s'
							, ${mainSchemaName}.f_valid_system_name(
								i_raw_name => t.key_value
								, i_is_considered_as_whole_name => false
							)
						)::name as partition_table_name
						, case 
							when t.key_value is not null then
								format(
									'for values in (%%L)'
									, t.key_value
								)
							else 
								'default'
						end as partition_expression
						, false as is_old
						, true as is_new
					from (
						select distinct 
							%s::varchar as key_value
						from 
							%I.%I
					) t
					$sql$
					, l_partitioned_table_rec.schema_name
					, l_partitioned_table_rec.table_name
					, i_partition_key
					, l_partitioned_table_rec.schema_name
					, l_partitioned_table_rec.table_name
				)
		;
	else
		return query
			select
				null::${type.system_object_id} as partition_table_id
				, l_partitioned_table_rec.schema_name as partition_schema_name
				, format(
					'%I_default'
					, l_partitioned_table_rec.table_name
				)::name as partition_table_name
				, 'default' as partition_expression
				, false as is_old
				, true as is_new
		;
	end if
	;
end
$function$
;

