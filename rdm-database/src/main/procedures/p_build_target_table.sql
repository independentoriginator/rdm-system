create or replace procedure p_build_target_table(
	i_type_rec record
)
language plpgsql
as $procedure$
declare 
	l_attr_rec record;
begin
	if i_type_rec.is_table_exists = false then 
		if i_type_rec.is_temporal = false then
			execute format('
				create table %I.%I(
					id %s not null generated by default as identity
				)'
				, '${database.defaultSchemaName}'
				, i_type_rec.internal_name
				, 'bigint'
			);
		else
			execute format('
				create table %I.%I(
					id %s not null generated by default as identity,
					version %s not null generated by default as identity,
					valid_from timestamp without time zone default current_timestamp not null,
					valid_to timestamp without time zone not null
				)'
				, '${database.defaultSchemaName}'
				, i_type_rec.internal_name
				, 'bigint'
				, 'bigint'
			);
		end if;
	else
		if i_type_rec.is_temporal = true and i_type_rec.is_target_table_non_temporal = true then
			if i_type_rec.is_localization_table_exists = true then 
				execute format('
					drop table %I.%I
					'
					, '${database.defaultSchemaName}'
					, i_type_rec.localization_table_name
				);
			end if;
			
			execute format('
				alter table %I.%I
					add column version %s not null generated by default as identity,
					add column valid_from timestamp without time zone default current_timestamp not null,
					add column valid_to timestamp without time zone not null
				'
				, '${database.defaultSchemaName}'
				, i_type_rec.internal_name
				, 'bigint'
			);
		end if;
	end if;

	if i_type_rec.is_pk_index_exists = false and i_type_rec.is_temporal = false then
		execute format('
			create unique index %I on %I.%I (
				id
			)'
			, i_type_rec.pk_index_name 
			, '${database.defaultSchemaName}'
			, i_type_rec.internal_name 
		);
	elsif i_type_rec.is_temporal = true then
		if i_type_rec.is_pk_index_exists = true and i_type_rec.is_target_table_non_temporal = true then
			execute format('
				alter table %I.%I drop constraint %I cascade;
				drop index %I.%I;
				'
				, '${database.defaultSchemaName}'
				, i_type_rec.internal_name 
				, i_type_rec.pk_index_name
				, '${database.defaultSchemaName}'
				, i_type_rec.pk_index_name
			);
		end if;
		
		execute format('
			create unique index %I on %I.%I (
				id, version
			)'
			, i_type_rec.pk_index_name 
			, '${database.defaultSchemaName}'
			, i_type_rec.internal_name 
		);
		execute format('
			create unique index ui_%I$id_valid_to on %I.%I (
				id, valid_to
			)'
			, i_type_rec.internal_name 
			, '${database.defaultSchemaName}'
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
			, '${database.defaultSchemaName}'
			, i_type_rec.internal_name 
			, i_type_rec.pk_index_name 
			, i_type_rec.pk_index_name				
		);
	end if;
	
	for l_attr_rec in (
		select
			a.*
		from 
			${database.defaultSchemaName}.v_meta_attribute a
		where 
			a.meta_type_id = i_type_rec.id
		order by 
			ordinal_position asc nulls last, 
			id asc 
	) 
	loop
		call ${database.defaultSchemaName}.p_build_target_column(
			i_attr_rec => l_attr_rec
		);
	end loop;	
	
	call ${database.defaultSchemaName}.p_build_target_lc_table(
		i_type_rec => i_type_rec
	);
	
end
$procedure$;			
