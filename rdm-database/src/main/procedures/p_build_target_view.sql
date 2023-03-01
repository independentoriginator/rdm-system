create or replace procedure p_build_target_view(
	i_view_rec record
)
language plpgsql
as $procedure$
declare
	l_msg_text text;
	l_exception_detail text;
	l_exception_hint text;
	l_exception_context text;
begin
	if i_view_rec.schema_id is not null and i_view_rec.is_schema_exists = false then
		execute format('
			create schema if not exists %I
			'
			, i_view_rec.schema_name
		);
	
		if length('${mainEndUserRole}') > 0 
	  	then
	  		execute format('
				grant usage on schema %I to ${mainEndUserRole}
				'
				, i_view_rec.schema_name
			);
		end if;
	end if;

	if i_view_rec.is_view_exists then
		-- Detecting and saving dependants before cascadly dropping them
		call ${mainSchemaName}.p_specify_meta_view_dependencies(
			i_view_name => i_view_rec.internal_name
			, i_schema_name => i_view_rec.schema_name
			, i_is_routine => i_view_rec.is_routine
			, i_treat_the_obj_as_dependent => false -- treat the object as master 
		);

		if not i_view_rec.is_routine then
			execute format('
				drop %sview if exists %I.%I cascade
				'
				, case when i_view_rec.is_materialized then 'materialized ' else '' end
				, i_view_rec.schema_name
				, i_view_rec.internal_name
			);
		end if;
	end if;

	if not i_view_rec.is_external 
		or not i_view_rec.is_routine
		or (
			not coalesce(i_view_rec.is_created, false) 
			and (
				not i_view_rec.is_external 
				or (
					-- external object must be recreated within current transaction only, during current dependencies recreation
					-- (if the object is deleted from the outside, then it should not be recreated)
					i_view_rec.is_external 
					and i_view_rec.modification_time = current_timestamp 
				)
			)
		)
	then
		begin
			execute i_view_rec.query;
		exception
			when others then
				get stacked diagnostics
					l_msg_text = MESSAGE_TEXT
					, l_exception_detail = PG_EXCEPTION_DETAIL
					, l_exception_hint = PG_EXCEPTION_HINT
					, l_exception_context = PG_EXCEPTION_CONTEXT
					;
				if not i_view_rec.is_external then 
					raise exception 
						'View creation error: %: % (hint: %, context: %)'
						, l_msg_text
						, l_exception_detail
						, l_exception_hint
						, l_exception_context
						;
				else 
					raise notice 
						'External view creation error: %: % (hint: %, context: %). The view will be disabled.'
						, l_msg_text
						, l_exception_detail
						, l_exception_hint
						, l_exception_context
						;
					update ${mainSchemaName}.meta_view 
					set is_disabled = true
						, modification_time = current_timestamp
					where id = i_view_rec.id
					;
				end if;	
		end;
	
		-- Main end user role
		if not i_view_rec.is_external 
			and length('${mainEndUserRole}') > 0 
		then
			execute	
				format(
					'grant %s %I.%s to ${mainEndUserRole}'
					, case when i_view_rec.is_routine then 'execute on routine ' else 'select on' end
					, i_view_rec.schema_name
					, i_view_rec.internal_name 
				
				);
		end if;
	elsif i_view_rec.is_external 
		and (i_view_rec.modification_time <> current_timestamp or i_view_rec.modification_time is null)	
	then
		raise notice 'Disabling non-actual external view %.%...', i_view_rec.schema_name, i_view_rec.internal_name;
		
		update ${mainSchemaName}.meta_view 
		set is_disabled = true
			, modification_time = current_timestamp
		where id = i_view_rec.id
		;
		return;
	end if;

	-- Actualize stored dependencies
	call ${mainSchemaName}.p_specify_meta_view_dependencies(
		i_view_name => i_view_rec.internal_name
		, i_schema_name => i_view_rec.schema_name
		, i_is_routine => i_view_rec.is_routine
		, i_treat_the_obj_as_dependent => true 
	);

	update ${mainSchemaName}.meta_view
	set 
		is_created = true
		, is_valid = false
		, dependency_level = (
			select 
				${mainSchemaName}.f_meta_view_dependency_level(i_view_oid => v.view_oid)
			from 
				${mainSchemaName}.v_meta_view v
			where 
				v.id = i_view_rec.id
		)
		, modification_time = current_timestamp
	where 
		id = i_view_rec.id
	;
end
$procedure$;			
