create or replace function f_default_language_id()
returns ${mainSchemaName}.language.id%type
language sql
stable
as $function$
select 
	coalesce((
			select 
				s.lang_id
			from 
				${mainSchemaName}.source s
			where	
				s.internal_name = 'manual data entry'
		)
		, (
			select 
				l.id 
			from 
				${mainSchemaName}.language l
			where 
				l.tag = 'en'
		)
	);
$function$;		