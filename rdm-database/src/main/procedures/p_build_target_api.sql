create or replace procedure p_build_target_api(
	i_type_rec record
)
language plpgsql
as $$
begin
	if i_type_rec.is_staging_table_generated = false then
		return;
	end if;
		
	execute format($target_procedure$
		create or replace procedure %I.p_apply_%I(
			i_data_package_id in %I.data_package.id%%type
			, io_check_date in out %I.data_package.state_change_date%%type
		)
		language plpgsql
		as $procedure$
		declare 
			l_data_package record := (
				select
					s.internal_name as state_name
					, p.state_change_date
					, p.is_deletion
				from 
					%I.data_package p
				join %I.data_package_state s on s.id = p.state_id
				where 
					p.id = i_data_package_id
				for update
			);
			l_state_change_date timestamp without time zone := current_timestamp;
		begin
			if io_check_date <> l_data_package.state_change_date then
				raise exception 'The data package has changed since it was accessed: %%', l_data_package.state_change_date
					using hint = 'Try to repeat the operation';
  			end if;
  			
  			if l_data_package.state_name <> 'created' then  
				raise exception 'The data package has unexpected state: %%', l_data_package.state_name;
  			end if;
  			
  			if l_data_package.is_deletion = false then
				insert into 
					%I.%I(
						%s
					)
				select 
					%s
				from 
					%I.%I t
				where 
					t.data_package_id = i_data_package_id
				on conflict (code, source_id) do update set
					%s	
				;
			else
				delete from
					%I.%I target_table
				where 
					exists (
						select 
							1
						from 
							%I.%I t
						where 
							t.data_package_id = i_data_package_id
							and t.code = target_table.code					
							and t.source_id = target_table.source_id
					)
				;
			end if;
				
			update 
				%I.data_package p
			set 
				state_id = (
					select 
						s.id
					from 
						%I.data_package_state s 
					where 
						s.internal_name = 'applied'
				)
				, state_change_date = l_state_change_date
			where 
				p.id = i_data_package_id
			;
			
			io_check_date := l_state_change_date;
		end
		$procedure$;
		$target_procedure$			
		, i_type_rec.schema_name
		, i_type_rec.internal_name
		, i_type_rec.staging_schema_name
		, i_type_rec.staging_schema_name
		, i_type_rec.staging_schema_name
		, i_type_rec.schema_name
		, i_type_rec.schema_name
		, i_type_rec.internal_name
		, i_type_rec.non_localisable_attributes
		, i_type_rec.non_localisable_attributes		
		, i_type_rec.staging_schema_name
		, i_type_rec.internal_name
		, i_type_rec.insert_expr_on_conflict_update_part
		, i_type_rec.schema_name
		, i_type_rec.internal_name
		, i_type_rec.staging_schema_name
		, i_type_rec.internal_name
		, i_type_rec.staging_schema_name
		, i_type_rec.schema_name
	);
end
$$;			
