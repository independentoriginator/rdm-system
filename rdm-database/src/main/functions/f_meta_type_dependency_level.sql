create or replace function f_meta_type_dependency_level(
	i_meta_type_id ${database.defaultSchemaName}.meta_type.id%type
)
returns integer
language sql
stable
as $function$
select 
	coalesce((
			select 
				max(${database.defaultSchemaName}.f_meta_type_dependency_level(i_meta_type_id => t.id))
			from (
				select distinct
					referenced_type.id as id
				from 
					${database.defaultSchemaName}.meta_attribute a 
				join ${database.defaultSchemaName}.meta_type referenced_type 
					on referenced_type.id = a.attr_type_id and referenced_type.is_primitive = false
				where 
					a.master_id = i_meta_type_id
				union 
				select 
					t.master_type_id as id
				from 
					${database.defaultSchemaName}.meta_type t 
				where 
					t.id = i_meta_type_id
					and t.master_type_id is not null
					and t.master_type_id <> t.id
			) t
		) + 1,
		0
	)
$function$;		