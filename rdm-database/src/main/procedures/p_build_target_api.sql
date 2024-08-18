create or replace procedure 
	p_build_target_api(
		i_type_rec record
	)
language plpgsql
as $$
declare
	l_check_section text;
	l_insert_proc_section text;
	l_delete_proc_section text;
	l_cte_option text := 
		case 
			when ${mainSchemaName}.f_is_server_feature_available('cte_explicitly_materializing') 
			then 'materialized ' 
			else '' 
		end
	;
begin
	if i_type_rec.is_staging_table_generated = false then
		return;
	end if;
	
	if i_type_rec.is_temporal = false then
		l_check_section := '';
		
		l_insert_proc_section := 
			format(
				$insert_section$
					l_row_offset := 0;
				
					<<data_insertion>>
					loop
						insert into 
							%I.%I(
								id, %s
							)
						select 
							coalesce(id, nextval('%I.%I_id_seq')), %s
						from 
							${stagingSchemaName}.%I t
						where 
							t.data_package_id = i_data_package_id
							and t.data_package_rn between l_row_offset + 1 and l_row_offset + l_row_limit
						on conflict (id) do update set
							record_date = l_state_change_date
							, %s	
						;
					
						l_row_offset := l_row_offset + l_row_limit;
					
						if l_row_offset >= l_data_package_row_count then
							exit data_insertion;
						end if;
					end loop data_insertion;
				$insert_section$
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.non_localisable_attributes
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.non_localisable_attributes		
				, i_type_rec.internal_name
				, i_type_rec.insert_expr_on_conflict_update_part
			);
	
		if i_type_rec.is_localization_table_generated then
			l_insert_proc_section := l_insert_proc_section || 
				format(
					$insert_section$
					l_row_offset := 0;
				
					<<localisable_data_insertion>>
					loop
						with 
							package_data as %s(
								select 
									t.id
									, t.data_package_id
									, t.data_package_rn
									, %s
								from 								
									${stagingSchemaName}.%I t
								where 
									t.data_package_id = i_data_package_id
									and t.data_package_rn between l_row_offset + 1 and l_row_offset + l_row_limit
							)
							, meta_attribute as %s(
								select 
									*
								from 
									${mainSchemaName}.v_meta_attribute a 
								where 
									a.meta_type_name = '%I'
									and a.is_localisable
							)						
							, localisable_data as %s(
								select 
									target_rec.id
									, master_rec.id as master_id
									, meta_attr.id as attr_id
									, p.lang_id
									, case meta_attr.internal_name
										%s
									end as lc_string
									, true as is_default_value
								from 
									package_data t
								cross join meta_attribute meta_attr
								join ${stagingSchemaName}.data_package p 
									on p.id = t.data_package_id
								join %I.%I master_rec
									on master_rec.data_package_id = t.data_package_id
									and master_rec.data_package_rn = t.data_package_rn
								left join %I.%I_lc target_rec
									on target_rec.master_id = master_rec.id
									and target_rec.attr_id = meta_attr.id
									and target_rec.lang_id = p.lang_id
									and target_rec.is_default_value
							) 
							, deleted_data as %s(
								delete from 
									%I.%I_lc dest
								using
									localisable_data src
								where 
									dest.id = src.id
									and src.lc_string is null
								returning 
									dest.id as deleted_id
							)
						insert into 
							%I.%I_lc(
								id
								, master_id
								, attr_id
								, lang_id
								, lc_string
								, is_default_value
							)
						select 
							coalesce(src.id, nextval('%I.%I_lc_id_seq')) as id
							, src.master_id
							, src.attr_id
							, src.lang_id
							, src.lc_string
							, src.is_default_value
						from 
							localisable_data src
						left join deleted_data d
							on d.deleted_id = src.id
						where 
							src.lc_string is not null
						on conflict (id) do update set
							lc_string = excluded.lc_string		
						;
				
						l_row_offset := l_row_offset + l_row_limit;
					
						if l_row_offset >= l_data_package_row_count then
							exit localisable_data_insertion;
						end if;
					end loop localisable_data_insertion;
					$insert_section$
					, l_cte_option
					, i_type_rec.localisable_attributes
					, i_type_rec.internal_name
					, l_cte_option
					, i_type_rec.internal_name
					, l_cte_option
					, i_type_rec.localisable_attr_case_expr_body
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, l_cte_option
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, i_type_rec.schema_name
					, i_type_rec.internal_name
				);
		end if;
		
		l_delete_proc_section := 
			format(
				$delete_section$
					delete from
						%I.%I dest
					using 
						${stagingSchemaName}.%I src
					where 
						src.data_package_id = i_data_package_id
						and dest.id = src.id
					;
				$delete_section$
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.internal_name
			);
		
	else
		l_check_section :=
			format(
				$check_section$
				<<row_actuality_check>>
				declare 
					l_id %I.%I.id%%type;
				begin
					select 
						src.id
					into 
						l_id
					from 
						${stagingSchemaName}.%I src
					join %I.%I dest
						on dest.id = src.id
						and dest.version = src.version
						and dest.valid_to <> ${mainSchemaName}.f_undefined_max_date() 
						and dest.external_version is null 
						and dest.meta_version is null 
					where 
						src.data_package_id = i_data_package_id
					limit 1
					;
				
					if l_id is not null then
						raise exception 
							'%I.%I: the data package (id = %%) includes non-actual record version (id = %%)'
							, i_data_package_id
							, l_id
							using hint = 'Try to recompile the data package';
					end if;
				end row_actuality_check;
				$check_section$
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.internal_name
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.schema_name
				, i_type_rec.internal_name
			);
			
		l_insert_proc_section := 
			format(
				$insert_section$
					update
						%I.%I dest
					set 
						valid_to = l_state_change_date
					from 
						${stagingSchemaName}.%I src
					where 
						src.data_package_id = i_data_package_id
						and dest.id = src.id
						and dest.version = src.version
						and dest.external_version is null 
						and dest.meta_version is null 
					;
				
					l_row_offset := 0;
				
					<<data_insertion>>
					loop
						with 
							package_data as %s(
								select 
									t.id
									, t.version
									, t.valid_from
									, t.valid_to
									, %s
									, row_number() over(
										partition by
											t.external_id
											, t.meta_id
										order by 
											t.external_id
											, t.external_version_ordinal_num
											, t.meta_id
											, t.meta_version_ordinal_num
											, t.valid_from
									) as version_ordinal_num
								from 								
									${stagingSchemaName}.%I t
								where 
									t.data_package_id = i_data_package_id
									and t.data_package_rn between l_row_offset + 1 and l_row_offset + l_row_limit									
							)
							, closed_old_external_versions as %s(
								update
									%I.%I dest
								set 
									valid_to = src.valid_from
								from 
									package_data src
								where 
									l_row_offset = 0
									and dest.valid_to = ng_rdm.f_undefined_max_date()
									and src.data_package_id = i_data_package_id
									and dest.external_id = src.external_id								
									and src.version_ordinal_num = 1
									and src.external_version is not null 
									and dest.external_version is not null 
									and (dest.data_package_id <> i_data_package_id or dest.data_package_id is null)
								returning 
									dest.id
									, dest.version
							)
							, closed_old_meta_versions as %s(
								update
									%I.%I dest
								set 
									valid_to = src.valid_from
								from 
									package_data src
								where 
									l_row_offset = 0
									and dest.valid_to = ng_rdm.f_undefined_max_date()
									and src.data_package_id = i_data_package_id
									and dest.meta_id = src.meta_id								
									and src.version_ordinal_num = 1
									and src.meta_version is not null 
									and dest.meta_version is not null 
									and (dest.data_package_id <> i_data_package_id or dest.data_package_id is null)
								returning 
									dest.id
									, dest.version
							)
							, initial_versions as %s(
								insert into 
									%I.%I(
										id
										, version
										, valid_from
										, valid_to
										, record_date
										, %s
									)
								select 
									coalesce(
										t.id
										, (
											select
												e.id
											from 
												%I.%I e 
											where 
												e.external_id = t.external_id
												and e.source_id = t.source_id
											order by 
												t.external_id
												, t.external_version_ordinal_num
												, t.valid_from
											limit 1
										)
										, (
											select
												e.id
											from 
												%I.%I e 
											where 
												t.external_id is null 
												and e.meta_id = t.meta_id
												and e.source_id = t.source_id
											order by 
												t.meta_id
												, t.meta_version_ordinal_num
												, t.valid_from
											limit 1
										)
										, nextval('%I.%I_id_seq')
									) as id
									, coalesce(
										case 
											when t.external_version is not null
												or t.meta_version is not null 
											then t.version
										end
										, nextval('%I.%I_version_seq')
									) as version
									, coalesce(
										t.valid_from
										, case 
											when t.id is null then ${mainSchemaName}.f_undefined_min_date()
											else l_state_change_date
										end
									) as valid_from
									, coalesce(
										t.valid_to
										, ${mainSchemaName}.f_undefined_max_date()
									) as valid_to
									, l_state_change_date
									, %s
								from 
									package_data t
								left join closed_old_external_versions oev
									on false
								left join closed_old_meta_versions omv
									on false
								where 
									t.version_ordinal_num = 1
								on conflict (id, version) do update set
									record_date = l_state_change_date
									, valid_from = excluded.valid_from
									, valid_to = excluded.valid_to
									, %s	
								returning 
									id as inserted_id
									, version as inserted_version
									, external_id as inserted_external_id
									, external_version as inserted_external_version
									, meta_id as inserted_meta_id
									, meta_version as inserted_meta_version
							)
						insert into 
							%I.%I(
								id
								, version
								, valid_from
								, valid_to
								, record_date
								, %s
							)
						select 
							t.id
							, coalesce(
								case 
									when t.external_version is not null
										or t.meta_version is not null 
									then t.version
								end
								, nextval('%I.%I_version_seq')
							) as version
							, coalesce(
								t.valid_from
								, l_state_change_date
							) as valid_from
							, coalesce(
								t.valid_to
								, ${mainSchemaName}.f_undefined_max_date()
							) as valid_to
							, l_state_change_date
							, %s
						from (						
							select 
								iv.inserted_id as id
								, t.version
								, t.valid_from
								, t.valid_to
								, %s
							from 								
								package_data t
							join initial_versions iv 
								on iv.inserted_external_id = t.external_id
							where
								t.version_ordinal_num > 1
								and t.external_id is not null
							union all
							select 
								iv.inserted_id as id
								, t.version
								, t.valid_from
								, t.valid_to
								, %s
							from 								
								package_data t
							join initial_versions iv 
								on iv.inserted_meta_id = t.meta_id
							where
								t.version_ordinal_num > 1
								and t.external_version is null
								and t.meta_version is not null
						) t
						order by 
							t.external_id
							, t.external_version_ordinal_num
							, t.meta_id
							, t.meta_version_ordinal_num
							, t.valid_from
						on conflict (id, version) do update set
							record_date = l_state_change_date
							, valid_from = excluded.valid_from
							, valid_to = excluded.valid_to
							, %s	
						;
					
						l_row_offset := l_row_offset + l_row_limit;
					
						if l_row_offset >= l_data_package_row_count then
							exit data_insertion;
						end if;
					end loop data_insertion;
				$insert_section$
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.internal_name
				, l_cte_option
				, i_type_rec.non_localisable_attributes
				, i_type_rec.internal_name
				, l_cte_option
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, l_cte_option
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, l_cte_option
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.non_localisable_attributes
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.non_localisable_attributes
 				, i_type_rec.insert_expr_on_conflict_update_part
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.non_localisable_attributes
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.non_localisable_attributes
				, i_type_rec.non_localisable_attributes
				, i_type_rec.non_localisable_attributes
 				, i_type_rec.insert_expr_on_conflict_update_part
			);
			
		if i_type_rec.is_localization_table_generated then
			l_insert_proc_section := l_insert_proc_section ||  
				format(
					$insert_section$
					l_row_offset := 0;
				
					<<localisable_data_insertion>>
					loop
						with 
							package_data as %s(
								select 
									t.id
									, t.version
									, t.valid_from
									, t.valid_to
									, t.data_package_id
									, t.data_package_rn
									, %s
								from 								
									${stagingSchemaName}.%I t
								where 
									t.data_package_id = i_data_package_id
									and t.data_package_rn between l_row_offset + 1 and l_row_offset + l_row_limit
							)
							, meta_attribute as %s(
								select 
									*
								from 
									${mainSchemaName}.v_meta_attribute a 
								where 
									a.meta_type_name = '%I'
									and a.is_localisable
							)	
							, localisable_data as %s(
								select 
									target_rec.id
									, master_rec.id as master_id
									, master_rec.version as master_version
									, meta_attr.id as attr_id
									, p.lang_id
									, case meta_attr.internal_name
										%s
									end as lc_string
									, true as is_default_value
								from 
									package_data t
								cross join meta_attribute meta_attr
								join ${stagingSchemaName}.data_package p 
									on p.id = t.data_package_id
								join %I.%I master_rec
									on master_rec.data_package_id = t.data_package_id
									and master_rec.data_package_rn = t.data_package_rn
								left join %I.%I_lc target_rec
									on target_rec.master_id = master_rec.id
									and target_rec.master_version = master_rec.version
									and target_rec.attr_id = meta_attr.id
									and target_rec.lang_id = p.lang_id
									and target_rec.is_default_value
							) 
							, deleted_data as %s(
								delete from 
									%I.%I_lc dest
								using
									localisable_data src
								where 
									dest.id = src.id
									and src.lc_string is null
								returning 
									dest.id as deleted_id
							)
						insert into 
							%I.%I_lc(
								id
								, master_id
								, master_version
								, attr_id
								, lang_id
								, lc_string
								, is_default_value
							)
						select 
							coalesce(src.id, nextval('%I.%I_lc_id_seq')) as id
							, src.master_id
							, src.master_version
							, src.attr_id
							, src.lang_id
							, src.lc_string
							, src.is_default_value
						from 
							localisable_data src
						left join deleted_data d
							on d.deleted_id = src.id
						where 
							src.lc_string is not null
						on conflict (id) do update set
							lc_string = excluded.lc_string		
						;
					
						l_row_offset := l_row_offset + l_row_limit;
					
						if l_row_offset >= l_data_package_row_count then
							exit localisable_data_insertion;
						end if;
					end loop localisable_data_insertion;
					$insert_section$
					, l_cte_option
					, i_type_rec.localisable_attributes
					, i_type_rec.internal_name
					, l_cte_option
					, i_type_rec.internal_name
					, l_cte_option
					, i_type_rec.localisable_attr_case_expr_body
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, l_cte_option					
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, i_type_rec.schema_name
					, i_type_rec.internal_name
				);
		end if;
			
		l_delete_proc_section := 
			format(
				$delete_section$
					update
						%I.%I dest
					set 
						valid_to = l_state_change_date
					from 
						${stagingSchemaName}.%I src
					where 
						src.data_package_id = i_data_package_id
						and dest.id = src.id
						and dest.version = src.version
						and dest.external_version is null 
						and dest.meta_version is null 
					;
				$delete_section$
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.internal_name
			) 
			|| case 
				when i_type_rec.is_localization_table_generated then
				format(
					$delete_section$
					delete from
						%I.%I_lc dest_lc
					using 
						${stagingSchemaName}.%I src
					join %I.%I dest
						on dest.id = src.id
						and dest.version = src.version
						and (
							dest.external_version is not null 
							or dest.meta_version is not null
						)
					where 
						src.data_package_id = i_data_package_id
						and dest_lc.master_id = dest.id
						and dest_lc.master_version = dest.version
					;
					$delete_section$
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, i_type_rec.internal_name
					, i_type_rec.schema_name
					, i_type_rec.internal_name
				) 
				else ''
			end 
			|| format(
				$delete_section$
					delete from
						%I.%I dest
					using 
						${stagingSchemaName}.%I src
					where 
						src.data_package_id = i_data_package_id
						and dest.id = src.id
						and dest.version = src.version
						and (
							dest.external_version is not null 
							or dest.meta_version is not null
						)
					;
				$delete_section$
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.internal_name
			);
	end if;
		
	execute format(
		$target_procedure$
		create or replace procedure %I.p_process_%I(
			i_data_package_id in ${stagingSchemaName}.data_package.id%%type
			, io_check_date in out ${stagingSchemaName}.data_package.state_change_date%%type
		)
		language plpgsql
		security definer
		as $procedure$
		declare 
			l_data_package record;
			l_state_change_date timestamp without time zone := ${mainSchemaName}.f_current_timestamp();
			l_data_package_row_count bigint;
			l_row_limit bigint := ${mainSchemaName}.f_operation_row_limit();
			l_row_offset bigint;
		begin
			select
				s.internal_name as state_name
				, p.state_change_date
				, p.is_deletion
				, p.type_id
			into 
				l_data_package
			from 
				${stagingSchemaName}.data_package p
			join ${mainSchemaName}.data_package_state s on s.id = p.state_id
			where 
				p.id = i_data_package_id
			for update of p
			;
			
			if io_check_date <> l_data_package.state_change_date then
				raise exception 'The data package has changed since it was accessed: %%', l_data_package.state_change_date
					using hint = 'Try to repeat the operation';
  			end if;
  			
  			if l_data_package.state_name <> 'loaded' then  
				raise exception 'The data package is in an unexpected state: %%', l_data_package.state_name;
  			end if;
  		
  			select 
  				count(*)
  			into
  				l_data_package_row_count
			from 
				${stagingSchemaName}.%I src
			where 
				src.data_package_id = i_data_package_id
			;
		
  			if l_data_package_row_count > 0 then
				call ${mainSchemaName}.p_invalidate_entity_dependent_views(
					i_type_id => l_data_package.type_id 
				);
	  			%s
	  			if l_data_package.is_deletion = false then
	  				%s
				else
					%s
				end if;
				%s
			end if;
		
			update 
				${stagingSchemaName}.data_package p
			set 
				state_id = (
					select 
						s.id
					from 
						${mainSchemaName}.data_package_state s 
					where 
						s.internal_name = 'processed'
				)
				, state_change_date = l_state_change_date
			where 
				p.id = i_data_package_id
			;
			
			io_check_date := l_state_change_date;
		end
		$procedure$;
	
		comment on routine %I.p_process_%I(
			${stagingSchemaName}.data_package.id%%type
			, ${stagingSchemaName}.data_package.state_change_date%%type
		) is $comment$%s$comment$
		$target_procedure$			
		, i_type_rec.schema_name
		, i_type_rec.internal_name
		, i_type_rec.internal_name
		, l_check_section
		, l_insert_proc_section
		, l_delete_proc_section
		, case 
			when exists (
				select 
					1 
				from
					pg_catalog.pg_proc p
				where 
					p.pronamespace = i_type_rec.schema_name::regnamespace
					and p.proname = 'p_after_processing_' || i_type_rec.internal_name
					and p.prokind = 'p'::"char"
					and 'i_data_package_id' = any(p.proargnames)
			) 
			then format('
					call %I.p_after_processing_%I(
						i_data_package_id => i_data_package_id
					); 
				'
				, i_type_rec.schema_name 
				, i_type_rec.internal_name
			)
			else ''
		end
		|| format(
			$analyze$
				analyze
					%I.%I
				;
			$analyze$
			, i_type_rec.schema_name
			, i_type_rec.internal_name
		) 
		|| case 
			when i_type_rec.is_localization_table_generated then
				format(
					E'\n\t\t\t\tanalyze\n\t\t\t\t\t%I.%I_lc\n\t\t\t\t;'
					, i_type_rec.schema_name
					, i_type_rec.internal_name
				) 
			else ''
		end
		, i_type_rec.schema_name
		, i_type_rec.internal_name
		, i_type_rec.table_description
	)
	;
end
$$
;

comment on procedure 
	p_build_target_api(
		record
	) is 'Генерация целевого API сущности'
;
