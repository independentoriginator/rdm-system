create or replace procedure p_build_target_table(
	i_type_rec record
)
language plpgsql
as $procedure$
declare 
	l_attr_rec record;
	l_index_rec record;
begin
	if i_type_rec.schema_id is not null and i_type_rec.is_schema_exists = false then
		execute format('
			create schema %I
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
					valid_to timestamp without time zone not null
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
					add column valid_to timestamp without time zone not null
				'
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, '${type.id}'
			);
		end if;
	end if;
	
	call ${database.defaultSchemaName}.p_build_target_staging_table(
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
		end if;
		
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
	
	if i_type_rec.master_type_id is not null and i_type_rec.is_ref_to_master_column_exists = false then
		if i_type_rec.is_temporal = true then 
			execute format('
				alter table %I.%I
					add column master_id %s not null,
					add column master_version %s not null
				'
				, i_type_rec.schema_name
				, i_type_rec.internal_name 
				, '${type.id}'
				, '${type.id}'
			);
			
			execute format('
				create index i_%I$master_id_version on %I.%I (
					master_id, master_version
				)'
				, i_type_rec.internal_name 
				, i_type_rec.schema_name
				, i_type_rec.internal_name 
			);
			
			execute format('
				alter table %I.%I
					add constraint fk_%I$master_id_version foreign key (master_id, master_version) references %I.%I(id, version),
					add constraint chk_%I$master_id_version check (case when master_id is null then 1 else 0 end = case when master_version is null then 1 else 0 end)
				'
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.internal_name 
				, i_type_rec.schema_name
				, i_type_rec.master_type_name
				, i_type_rec.internal_name 
			);
		else
			execute format('
				alter table %I.%I
					add column master_id %s not null
				'
				, i_type_rec.schema_name
				, i_type_rec.internal_name 
				, '${type.id}'
			);
			
			execute format('
				create index i_%I$master_id on %I.%I (
					master_id
				)'
				, i_type_rec.internal_name 
				, i_type_rec.schema_name
				, i_type_rec.internal_name 
			);
			
			execute format('
				alter table %I.%I
					add constraint fk_%I$master_id foreign key (master_id) references %I.%I(id)
				'
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.internal_name 
				, i_type_rec.schema_name
				, i_type_rec.master_type_name
			);
		end if;

	end if;
	
	for l_attr_rec in (
		select
			a.*
		from 
			${database.defaultSchemaName}.v_meta_attribute a
		where 
			a.master_id = i_type_rec.id
		order by 
			ordinal_position asc nulls last, 
			id asc 
	) 
	loop
		call ${database.defaultSchemaName}.p_build_target_column(
			i_type_rec => i_type_rec,
			i_attr_rec => l_attr_rec
		);
	end loop;	
	
	for l_index_rec in (
		select
			i.*
		from 
			${database.defaultSchemaName}.v_meta_index i
		where 
			i.master_id = i_type_rec.id
	) 
	loop
		call ${database.defaultSchemaName}.p_build_target_index(
			i_index_rec => l_index_rec
		);
	end loop;
	
	call ${database.defaultSchemaName}.p_build_target_lc_table(
		i_type_rec => i_type_rec
	);

	call ${database.defaultSchemaName}.p_build_target_api(
		i_type_rec => i_type_rec
	);
end
$procedure$;			
