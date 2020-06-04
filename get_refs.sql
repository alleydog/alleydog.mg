CREATE OR REPLACE FUNCTION public.get_refs(v_table_name text, link_id bigint)
 RETURNS TABLE(sql text, id text)
 LANGUAGE plpgsql
AS $function$
declare
    row    record;
    result record;
    sql    text;
    result_sql text;
begin

    result_sql := 'select s.* from ( values ';

    for row in
        select b.relname as table_name,
               d.attname as column_name
        from pg_constraint a,
             pg_class b,
             pg_class c,
             pg_attribute d
        where a.contype = 'f'
          and b.oid = a.conrelid
          and c.oid = a.confrelid
          and c.relname = lower(v_table_name)
          and d.attrelid = b.oid
          and a.conkey[1] = d.attnum
        loop

            sql = 'select ' || row.column_name || ' as r from ' || row.table_name || ' where ' || row.column_name ||
                  ' = ' || link_id;
            execute sql into result;

            result_sql := result_sql || '('''|| sql ||''', '||''''|| coalesce(result.r, -1)|| '''' ||'),';

        end loop;

    result_sql := substr(result_sql, 1, length(result_sql) - 1)  || ') s (sql, id) order by 2 desc;';
    raise notice 'S %', result_sql;

    return query execute result_sql;
end
$function$
;
