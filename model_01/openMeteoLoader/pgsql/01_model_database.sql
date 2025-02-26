create schema if not exists modeling;

set search_path = modeling;

create table if not exists weather_data(
        weather_data_id bigint primary key generated always as identity ,
        model_name varchar(10),
        m_time timestamp,
        m_temperature float,
        m_humidity int
    );