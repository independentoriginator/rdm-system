create or replace procedure p_build_target_tables()
language plpgsql
as $procedure$
declare 
	l_type_rec record;
begin
	for l_type_rec in (
		select
			t.*
		from 
			${database.defaultSchemaName}.v_meta_type t
		order by 
			dependency_level desc
	) 
	loop
		call ${database.defaultSchemaName}.p_build_target_table(
			i_type_rec => l_type_rec
		);
	end loop;
end
$procedure$;			
