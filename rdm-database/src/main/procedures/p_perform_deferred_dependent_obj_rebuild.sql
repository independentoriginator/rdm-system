create or replace procedure p_perform_deferred_dependent_obj_rebuild()
language plpgsql
as $procedure$
declare 
	l_temp_table name := (
		select 
			t.relname
		from 
			pg_catalog.pg_class t
		where 
			t.relnamespace = pg_my_temp_schema()
			and t.relname = 't_pending_rebuild_dependent_sys_obj'
	);
	l_rec record;
begin
	if l_temp_table is not null then
		for l_rec in execute 
			format('
				select 
					name
					, definition
				from
					%I
				order by 
					iteration_num desc
					, dep_level
				'
				, l_temp_table
			)
		loop
			raise notice 'Deferred re-creation of the dependent object %...', l_rec.name;
	  		execute 
	  			l_rec.definition
	  		;
		end loop;
	
		execute 
			format('
				drop table %I;
				drop sequence %I_iteration_seq;
				'
				, l_temp_table
				, l_temp_table
			)
			;
	end if;
end
$procedure$;	

comment on procedure p_perform_deferred_dependent_obj_rebuild(
) is 'Выполнение отложенного восстановления зависимых объектов';

