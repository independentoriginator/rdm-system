create or replace procedure p_build_target_table(
	i_type_rec record
)
language plpgsql
as $procedure$
declare 
	l_attr_rec record;
	l_index_rec record;
	l_is_pk_index_exists boolean := i_type_rec.is_pk_index_exists;
	l_table_rec record;
begin
	if i_type_rec.schema_id is not null and i_type_rec.is_schema_exists = false then
		execute format('
			create schema if not exists %I
			'
			, i_type_rec.schema_name
		);
	end if;
	
	if i_type_rec.is_table_exists = false then 
		if i_type_rec.is_temporal = false then
			execute format('
				create table %I.%I(
					id %s not null generated by default as identity,
					record_date timestamp without time zone default current_timestamp not null
				)'
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, '${type.id}'
			);
		else
			execute format('
				create table %I.%I(
					id %s not null generated by default as identity,
					version %s not null generated by default as identity,
					valid_from timestamp without time zone default current_timestamp not null,
					valid_to timestamp without time zone not null,
					record_date timestamp without time zone default current_timestamp not null	
				)'
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, '${type.id}'
				, '${type.id}'
			);
		end if;
	else
		if i_type_rec.is_temporal = true and i_type_rec.is_target_table_non_temporal = true then
			if i_type_rec.is_localization_table_exists = true then 
				execute format('
					drop table %I.%I
					'
					, i_type_rec.schema_name
					, i_type_rec.localization_table_name
				);
			end if;
			
			execute format('
				alter table %I.%I
					add column version %s not null generated by default as identity,
					add column valid_from timestamp without time zone default current_timestamp not null,
					add column valid_to timestamp without time zone not null,
				'
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, '${type.id}'
			);
		end if;
	end if;
	
	call ${mainSchemaName}.p_build_target_staging_table(
		i_type_rec => i_type_rec
	);

	if i_type_rec.is_pk_index_exists = false and i_type_rec.is_temporal = false then
		execute format('
			create unique index %I on %I.%I (
				id
			)'
			, i_type_rec.pk_index_name 
			, i_type_rec.schema_name
			, i_type_rec.internal_name 
		);
	elsif i_type_rec.is_temporal = true then
		if i_type_rec.is_pk_index_exists = true and i_type_rec.is_target_table_non_temporal = true then
			execute format('
				alter table %I.%I drop constraint %I cascade;
				drop index %I.%I;
				'
				, i_type_rec.schema_name
				, i_type_rec.internal_name 
				, i_type_rec.pk_index_name
				, i_type_rec.schema_name
				, i_type_rec.pk_index_name
			);
			l_is_pk_index_exists := false;
		end if;
		
		if l_is_pk_index_exists = false then
			execute format('
				create unique index %I on %I.%I (
					id, version
				)'
				, i_type_rec.pk_index_name 
				, i_type_rec.schema_name
				, i_type_rec.internal_name 
			);
			execute format('
				create unique index ui_%I$id_valid_to on %I.%I (
					id, valid_to
				)'
				, i_type_rec.internal_name 
				, i_type_rec.schema_name
				, i_type_rec.internal_name 
			);
		end if;
	end if;

	if i_type_rec.is_pk_constraint_exists = false 
		or (i_type_rec.is_temporal = true and i_type_rec.is_target_table_non_temporal = true) 
	then 
		execute format('
			alter table %I.%I
				add constraint %I primary key using index %I
			'
			, i_type_rec.schema_name
			, i_type_rec.internal_name 
			, i_type_rec.pk_index_name 
			, i_type_rec.pk_index_name				
		);
	end if;
	
	if nullif(i_type_rec.table_description, i_type_rec.target_table_description) is not null then
		execute format($$
			comment on table %I.%I is $comment$%s$comment$
			$$
			, i_type_rec.schema_name
			, i_type_rec.internal_name
			, i_type_rec.table_description
		);
	end if;	
	
	for l_attr_rec in (
		select
			a.*
		from 
			${mainSchemaName}.v_meta_attribute a
		where 
			a.master_id = i_type_rec.id
		order by 
			ordinal_position asc nulls last, 
			id asc 
	) 
	loop
		call ${mainSchemaName}.p_build_target_column(
			i_type_rec => i_type_rec,
			i_attr_rec => l_attr_rec
		);
		call ${mainSchemaName}.p_build_target_staging_table_column(
			i_type_rec => i_type_rec,
			i_attr_rec => l_attr_rec
		);
	end loop;	
	
	for l_index_rec in (
		select
			i.*
		from 
			${mainSchemaName}.v_meta_index i
		where 
			i.master_id = i_type_rec.id
	) 
	loop
		call ${mainSchemaName}.p_build_target_index(
			i_index_rec => l_index_rec
		);
	end loop;
	
	call ${mainSchemaName}.p_build_target_lc_table(
		i_type_rec => i_type_rec
	);

	call ${mainSchemaName}.p_build_target_api(
		i_type_rec => i_type_rec
	);
	
	for l_table_rec in (
		select i_type_rec.schema_name, i_type_rec.internal_name
		where i_type_rec.internal_name not like 'meta\_%'
		union all
		select i_type_rec.schema_name, i_type_rec.localization_table_name
		where i_type_rec.is_localization_table_generated = true
			and i_type_rec.internal_name not like 'meta\_%'
	) 
	loop
		execute format($$
			drop trigger if exists tr_invalidate_dependent_views on %I.%I;
			create trigger tr_invalidate_dependent_views
			before insert or update or delete 
			on %I.%I
			for each statement 
			execute function ${mainSchemaName}.trf_entity_invalidate_dependent_views();
			$$
			, l_table_rec.schema_name
			, l_table_rec.internal_name
			, l_table_rec.schema_name
			, l_table_rec.internal_name
		);
	end loop;
		
	update ${mainSchemaName}.meta_type 
	set is_built = true
	where id = i_type_rec.id
	;
end
$procedure$;			
