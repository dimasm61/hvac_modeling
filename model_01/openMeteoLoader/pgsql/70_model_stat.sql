select  w.model_name, count(*)
from meteo.model.weather_data as w
group by w.model_name