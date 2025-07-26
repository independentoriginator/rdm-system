drop procedure if exists 
	p_alter_obj_with_dep_obj_recreation(
		${mainSchemaName}.v_sys_obj.obj_name%type
		, ${mainSchemaName}.v_sys_obj.obj_schema%type
		, ${mainSchemaName}.v_sys_obj.obj_class%type
		, text
		, boolean
		, boolean
	)
;

create or replace procedure 
	p_alter_obj_with_dep_obj_recreation(
		i_obj_name ${mainSchemaName}.v_sys_obj.obj_name%type
		, i_obj_schema ${mainSchemaName}.v_sys_obj.obj_schema%type
		, i_obj_class ${mainSchemaName}.v_sys_obj.obj_class%type
		, i_ddl_sttmnt text
		, i_defer_dependent_obj_recreation boolean = false -- calling p_perform_deferred_dependent_obj_rebuild before the session completion is expected
		, i_enforce_nodata_for_dependent_matview_being_recreated boolean = false
		, i_dep_obj_type "char"[] = null
	)
language plpgsql
as $procedure$
declare 
	l_dependent_objs_deletion_script jsonb[];
	l_dependent_objs_creation_script jsonb;
	l_dependent_obj jsonb;
	l_iteration_num integer;
begin
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
						, i_obj_name
						, 'obj_schema'			
						, i_obj_schema
						, 'obj_class'
						, i_obj_class
					)
				)
			, i_treat_the_obj_as_dependent => false
		) dependent_obj 
	where 
		dependent_obj.dep_obj_class = 'relation'
		-- excluding subindexes of a partial index 
		and ( 
			dependent_obj.dep_level = 1
			or dependent_obj.dep_obj_type <> 'i'
		)
		and (
			dependent_obj.dep_obj_type = any(i_dep_obj_type)
			or i_dep_obj_type is null 
		)
	;	
	
	if l_dependent_objs_deletion_script is not null then
		foreach l_dependent_obj in array l_dependent_objs_deletion_script loop
			raise notice 'Dropping the dependent object %...', l_dependent_obj->>'name'
			; 
			execute 
				l_dependent_obj->>'command'
			;
		end loop
		;
	end if
	;
		
	raise notice 
		'Altering the % object %.%...'
		, i_obj_class
		, i_obj_schema
		, i_obj_name
	;
	execute 
		i_ddl_sttmnt
	;

	if l_dependent_objs_deletion_script is not null then
		if i_defer_dependent_obj_recreation then 
			raise notice 
				'Re-creation of the dependent objects has been deferred. '
				'Don''t forget to call the p_perform_deferred_dependent_obj_rebuild procedure before the session completion.'
			;
			create temporary table if not exists 
				t_pending_rebuild_dependent_sys_obj(
					id oid not null
					, name text not null
					, definition text null
					, dep_level integer not null
					, iteration_num integer not null
					, primary key(id)
				)
			;
			create temporary sequence if not exists 
				t_pending_rebuild_dependent_sys_obj_iteration_seq
			;
			l_iteration_num := nextval('t_pending_rebuild_dependent_sys_obj_iteration_seq')
			;
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
					jsonb_array_elements(
						l_dependent_objs_creation_script
					) as obj(attrs)
			) 
			loop
				raise notice 
					'Re-creating the dependent object %...'
					, l_dependent_obj->>'name'
				; 
				execute 
					l_dependent_obj->>'definition'
				;
			end loop
			;
		end if
		;
	end if
	;
end
$procedure$
;	