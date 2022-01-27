create or replace function f_column_type_specification(
	i_data_type information_schema.columns.data_type%type
	, i_character_maximum_length information_schema.columns.character_maximum_length%type
	, i_numeric_precision information_schema.columns.numeric_precision%type
	, i_numeric_scale information_schema.columns.numeric_scale%type	
	, i_datetime_precision information_schema.columns.datetime_precision%type	
)
returns varchar
language sql
immutable
as $function$
select 
	case i_data_type
		when 'character varying' 
			then i_data_type ||
				case when i_character_maximum_length is not null
					then '(' || i_character_maximum_length || ')'
					else ''
				end
		when 'numeric' 
			then i_data_type ||
				case when i_numeric_precision is not null
					then '(' || i_numeric_precision::text || ', ' || coalesce(i_numeric_scale, 0)::text || ')'
					else ''
				end
		when 'timestamp without time zone' 
			then 'timestamp (' || coalesce(i_datetime_precision, 6)::text || ') without time zone'
		else 
			i_data_type
	end
$function$;		