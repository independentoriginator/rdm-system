drop procedure if exists p_alter_table_column_type(
	name
	, name
	, name
	, varchar
)
;

drop procedure if exists p_alter_table_column_type(
	name
	, name
	, name
	, varchar
	, boolean
)
;

create or replace procedure p_alter_table_column_type(
	i_schema_name name
	, i_table_name name
	, i_column_name name
	, i_column_type varchar
	, i_defer_dependent_obj_recreation boolean = false -- calling p_perform_deferred_dependent_obj_rebuild before the session completion is expected
	, i_enforce_nodata_for_dependent_matview_being_recreated boolean = false
)
language plpgsql
as $procedure$
declare 
	l_ddl_expr text;
	l_dependent_objs_deletion_script jsonb[];
	l_dependent_objs_creation_script jsonb;
	l_dependent_obj jsonb;
	l_iteration_num integer;
begin
	select
		format('
			alter %stable %I.%I
				alter column %I set data type %s%s
			'
			, case when c.relkind = 'f' then 'foreign ' else '' end 
			, i_schema_name
			, i_table_name
			, i_column_name
			, i_column_type
			, case
				when c.relkind <> 'f' then
					 format(
					 	' using %I::%s'
						, i_column_name
						, i_column_type
					)
				else 
					''
			end
		) 
	into
		l_ddl_expr
	from 
		pg_catalog.pg_class c
	join pg_catalog.pg_namespace s
		on s.oid = c.relnamespace
	where
		c.relname = i_table_name
		and s.nspname = i_schema_name
	;	
	
	select 
		array_agg( 
			jsonb_build_object(
				'name'
				, dependent_obj.dep_obj_schema || '.' || dependent_obj.dep_obj_name
				, 'command'
				, ${mainSchemaName}.f_sys_obj_drop_command(
					i_obj_class => dependent_obj.dep_obj_class
					, i_obj_id => dependent_obj.dep_obj_id
					, i_cascade => false
				)
			)
			order by dependent_obj.dep_level desc
		) as dependent_objs_deletion_script
		, jsonb_agg( 
			jsonb_build_object(
				'id'
				, dependent_obj.dep_obj_id
				, 'name'
				, dependent_obj.dep_obj_schema || '.' || dependent_obj.dep_obj_name
				, 'definition'
				, ${mainSchemaName}.f_sys_obj_definition(
					i_obj_class => dependent_obj.dep_obj_class
					, i_obj_id => dependent_obj.dep_obj_id
					, i_enforce_nodata_for_matview => i_enforce_nodata_for_dependent_matview_being_recreated
				)
				, 'dep_level'
				, dependent_obj.dep_level
			)
			order by dependent_obj.dep_level asc
		) as dependent_objs_creation_script
	into
		l_dependent_objs_deletion_script
		, l_dependent_objs_creation_script
	from 
		${mainSchemaName}.f_sys_obj_dependency(
			i_objects =>
				jsonb_build_array( 
					jsonb_build_object(
						'obj_name' 
						, i_table_name
						, 'obj_schema'			
						, i_schema_name
						, 'obj_class'
						, 'relation'
					)
				)
			, i_treat_the_obj_as_dependent => false
		) dependent_obj 
	where 
		dependent_obj.dep_obj_class = 'relation'
	;	
	
	if l_dependent_objs_deletion_script is not null then
		foreach l_dependent_obj in array l_dependent_objs_deletion_script loop
			raise notice 'Dropping the dependent object %...', l_dependent_obj->>'name'; 
			execute l_dependent_obj->>'command';
		end loop;
	end if;
		
	raise notice 'Altering the table column type %.%.%...', i_schema_name, i_table_name, i_column_name;
	execute l_ddl_expr;

	if l_dependent_objs_deletion_script is not null then
		
		if i_defer_dependent_obj_recreation then 
			raise notice 
				'Re-creation of the dependent objects has been deferred. '
				'Don''t forget to call the p_perform_deferred_dependent_obj_rebuild procedure before the session completion.';

			create temporary table if not exists t_pending_rebuild_dependent_sys_obj(
				id oid not null
				, name text not null
				, definition text not null
				, dep_level integer not null
				, iteration_num integer not null
				, primary key(id)
			)
			;
		
			create temporary sequence if not exists t_pending_rebuild_dependent_sys_obj_iteration_seq;
		
			l_iteration_num := nextval('t_pending_rebuild_dependent_sys_obj_iteration_seq');
		
			insert into 	
				t_pending_rebuild_dependent_sys_obj(
					id
					, name
					, definition
					, dep_level
					, iteration_num
				)
			select 
				obj.id
				, obj.name
				, obj.definition
				, obj.dep_level
				, l_iteration_num
			from 
				jsonb_to_recordset(l_dependent_objs_creation_script) 
					as obj(
						id oid
						, name text
						, definition text
						, dep_level integer
					)
			on conflict (id)
				do update set
					name = excluded.name
					, definition = excluded.definition
					, dep_level = excluded.dep_level
					, iteration_num = excluded.iteration_num
			;					
		else
			for l_dependent_obj in (
				select 
					obj.attrs
				from 
					jsonb_array_elements(l_dependent_objs_creation_script) as obj(attrs)
			) 
			loop
				raise notice 'Re-creating the dependent object %...', l_dependent_obj->>'name'; 
				execute l_dependent_obj->>'definition';
			end loop;
		end if;
	
	end if;

end
$procedure$;	

comment on procedure p_alter_table_column_type(
	name
	, name
	, name
	, varchar
	, boolean
	, boolean
) is 'Изменение типа столбца таблицы';

drop procedure if exists ${stagingSchemaName}.p_alter_table_column_type(
	name
	, name
	, name
	, varchar
)
;

drop procedure if exists ${stagingSchemaName}.p_alter_table_column_type(
	name
	, name
	, name
	, varchar
	, boolean
)
;

create or replace procedure ${stagingSchemaName}.p_alter_table_column_type(
	i_schema_name name
	, i_table_name name
	, i_column_name name
	, i_column_type varchar
	, i_defer_dependent_obj_recreation boolean = false
	, i_enforce_nodata_for_dependent_matview_being_recreated boolean = false
)
language plpgsql
as $procedure$
begin
	call ${mainSchemaName}.p_alter_table_column_type(
		i_schema_name => i_schema_name
		, i_table_name => i_table_name
		, i_column_name => i_column_name
		, i_column_type => i_column_type
		, i_defer_dependent_obj_recreation => i_defer_dependent_obj_recreation
		, i_enforce_nodata_for_dependent_matview_being_recreated => i_enforce_nodata_for_dependent_matview_being_recreated
	);
end
$procedure$;			

comment on procedure ${stagingSchemaName}.p_alter_table_column_type(
	name
	, name
	, name
	, varchar
	, boolean
	, boolean
) is 'Изменение типа столбца таблицы';
