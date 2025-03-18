set search_path = modeling;

drop function if exists simulation1;

create or replace function simulation1()
    returns table
            (
                num                        int,
                dt                         timestamp,
                temp_outdoor               float,
                air_flow                   float,
                temp_indoor_intake         float,
                temp_delta                 float,
                temp_outdoor_heating_off   float,
                kwh_heating                float,          -- мощность на нагрев temp_delta
                kwh_cost_unit              decimal(10, 2), -- стоимость кВтч
                kwh_cost_total             decimal(10, 2), -- стоимость киловат в рублях


                e_temp_indoor_exhaust      float,          -- температура в доме, будет на рекуп подаваться
                e_temp_outdoor_heating_off float,          -- выше этой температры не догреваем
                e_temp_pre_heating         float,          -- температура после нагрева

                e_temp_delta_pre_heating   float,
                e_kwh_pre_heating          decimal(10, 2), -- мощность на преднагрев

                e_efficiency               float,          -- КПД рекуператора

                e_temp_in_exchanger        float,          -- на входе рекупертора
                e_temp_out_exchanger       float,          -- температура после рекуператора
                e_temp_delta_work          float,

                e_temp_delta_post_heating  float,
                e_kwh_post_heating         decimal(10, 2), -- мощность на догрев

                e_kwh_cost_pre_heating     decimal(10, 2), -- затраты на преднагрев
                e_kwh_cost_post_heating    decimal(10, 2), -- затраты на догрев

                e_kwh_heating_total        float,

                e_kwh_cost_total           numeric(10, 2)  -- Общие затраты в рубля с рекуперацией
            )
    language plpgsql
as
$$
declare
    row            record;
    counter        int = 1;

begin
    for row in select *
               from modeling.weather_data
               where model_name = 'SKhb'
                 --and date_part('month', m_time) = 5
                 --and m_time = '2024-05-01 09:00:00.000000'::timestamp
        --and  ( m_time = '2024-01-05 07:00:00.000000'::timestamp
        --  or m_time = '2024-01-05 06:00:00.000000'::timestamp)
        loop
            num := counter;
            dt := row.m_time;
            temp_outdoor := row.m_temperature;

            --------------------------------------------------------------------------------
            -- Температура выпуска из дома, подаётся в ПВУ
            e_temp_indoor_exhaust = 25;

            -- температура которая должна быть на решётке в доме
            temp_indoor_intake := modeling.get_indoor_temperature_by_day(temp_outdoor, dt);

            if date_part('month',dt) in (10,11,12,1,2,3,4) then
                -- сезон отопления, батареи открываем посильнее
                -- воздух подаём холоднее
                temp_indoor_intake = 18;

                -- дома догрев ототплением, тепло в рекуп пойдёт тёплый воздух
                e_temp_indoor_exhaust = 25;
            end if;
            if date_part('month',dt) in (5, 9) then
                -- уже холодно, но сезон отопления не начался/закончился
                -- воздухом будем пытаться греться
                temp_indoor_intake = 25;

                -- дома не жарко, отопления нет
                e_temp_indoor_exhaust = 20;
            end if;
            if date_part('month',dt) in (6, 7, 8) then
                -- лето, но может быть холодно временами, отопления нет
                temp_indoor_intake = 20;

                -- дома как ну улице +3 градуса, но не ниже чем 20
                e_temp_indoor_exhaust := temp_outdoor;
                if e_temp_indoor_exhaust < temp_indoor_intake then
                    e_temp_indoor_exhaust := temp_indoor_intake;
                end if;
            end if;

            -- в ПУ перестаём догревать после этой температуры
            temp_outdoor_heating_off = 20;

            -- в ПВУ ниже этой температуры включаем преднагрев
            e_temp_pre_heating := -8;

            -- в ПВУ выше этой температуры не п
            e_temp_outdoor_heating_off := +3;


            --------------------------------------------------------------------------------
            air_flow := modeling.get_air_exchange_by_hour_and_speed(row.m_time);
            --------------------------------------------------------------------------------

            if temp_indoor_intake < temp_outdoor then
                -- если на улице теплее чем должно быть на решётке, то пусть дома будет как на улице
                temp_indoor_intake := row.m_temperature;
            end if;

            -- дельта на которой должна работать ПУ
            if row.m_temperature between -60 and temp_indoor_intake then
                -- если температура на улице ниже чем ожидается на решётках - греть нужно
                temp_delta := temp_indoor_intake - row.m_temperature;
            else
                -- температура выше, греть не будем
                temp_delta := 0;
            end if;

            -- затраты на нагрев в ПУ
            kwh_heating := modeling.get_kwh_for_heating(air_flow, temp_delta);
            kwh_cost_unit := modeling.get_kwh_cost(row.m_time);
            kwh_cost_total := kwh_cost_unit * kwh_heating;
            --------------------------------------------------------------------------------

            -- ПВУ ПРЕДНАГрЕВ
            if temp_outdoor between -60 and e_temp_pre_heating then
                -- должен быть преднагрев
                e_temp_delta_pre_heating := abs(e_temp_pre_heating - temp_outdoor);
                e_kwh_pre_heating := modeling.get_kwh_for_heating(air_flow, e_temp_delta_pre_heating);
                e_kwh_cost_pre_heating := kwh_cost_unit * e_kwh_pre_heating;

                -- на вход рекупа - до скольки преднагреваем (-8)
                e_temp_in_exchanger = e_temp_pre_heating;

            else
                -- не должно быть преднагрева
                e_temp_delta_pre_heating := 0;
                e_kwh_pre_heating := 0;
                e_kwh_cost_pre_heating := 0;

                -- на вход рекупа - то что с улицы
                e_temp_in_exchanger = temp_outdoor;
            end if;


            -- ПВУ РЕКУПЕРАТОР

            -- КПД рекуператора
            e_efficiency := modeling.get_exchanger_efficiency(
                    air_flow,
                    e_temp_in_exchanger, -- что на входе рекупа
                    e_temp_indoor_exhaust, -- что рекуп забирает из дома
                    0.85);

            e_temp_out_exchanger
                := modeling.get_exchanger_temp(
                    e_efficiency, e_temp_in_exchanger, e_temp_indoor_exhaust);

            -- дельта на которой работал рекуп
            e_temp_delta_work := e_temp_indoor_exhaust - e_temp_in_exchanger;

            -- ПВУ ДОГрЕВ
            if e_temp_out_exchanger < temp_indoor_intake then
                -- если на выходе из рекупа ниже температура чем ожидается на решётке, нужно догревать
                e_temp_delta_post_heating := temp_indoor_intake - e_temp_out_exchanger;
                e_kwh_post_heating := modeling.get_kwh_for_heating(air_flow, e_temp_delta_post_heating);
                e_kwh_cost_post_heating := kwh_cost_unit * e_kwh_post_heating;
            else
                -- если температура на выходе из решётки больше чем ожидается - не догреваем
                e_temp_delta_post_heating := 0;
                e_kwh_post_heating := 0;
                e_kwh_cost_post_heating := 0;
            end if;

            -- общие затраты
            e_kwh_cost_total := e_kwh_cost_pre_heating + e_kwh_cost_post_heating;
            e_kwh_heating_total := e_kwh_pre_heating + e_kwh_post_heating;

            counter := counter + 1;

            return next;

        end loop;
end;
$$;

select num
     , dt
     , air_flow
     , temp_outdoor
     , temp_indoor_intake
     , temp_delta
     , kwh_heating
     , kwh_cost_unit
     , kwh_cost_total
from modeling.simulation1();

select  date_part('year' , s.dt) as year
      , date_part('month', s.dt) as month
      , date_part('day'  , s.dt) as day
      , date_part('hour' , s.dt) as hour
      , min(temp_outdoor)   as temp_outdoor_min
      , max(temp_outdoor)   as temp_outdoor_max
      , avg(temp_indoor_intake)   as temp_indoor
      , sum(kwh_heating)    as kwh_heating
      , max(kwh_cost_unit)  as kwh_cost_unit
      , sum(kwh_cost_total) askwh_cost_total
from modeling.simulation1() as s
group by date_part('year', s.dt), date_part('month', s.dt), date_part('day', s.dt), date_part('hour'  , s.dt)
order by date_part('year', s.dt), date_part('month', s.dt), date_part('day', s.dt), date_part('hour'  , s.dt)
;


select date_part('year', s.dt)  as                 year
     , date_part('month', s.dt) as                 month
     --, date_part('day', s.dt) as day
     --, date_part('hour', s.dt) as day
     , round(min(s.temp_outdoor  )::numeric, 2)    temp_min
     , round(max(s.temp_outdoor  )::numeric, 2)    temp_max
     , round(avg(s.temp_outdoor  )::numeric, 2)    temp_avg
     , round(sum(s.kwh_heating   )::numeric, 2)    kWh
     , round(sum(s.kwh_cost_total), 2)             cost
     , ''
     , round(sum(s.e_kwh_heating_total)::numeric, 2)    kWh
     , round(sum(s.e_kwh_cost_total  ), 2)             cost

from modeling.simulation1() as s
group by date_part('year', s.dt), date_part('month', s.dt)--, date_part('day', s.dt), date_part('hour', s.dt)
order by date_part('year', s.dt), date_part('month', s.dt)--, date_part('day', s.dt), date_part('hour', s.dt)
