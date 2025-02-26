package main

import "time"

type OpenMeteoResponseModel struct {
	Latitude             float64     `json:"latitude"`
	Longitude            float64     `json:"longitude"`
	GenerationTimeMs     float64     `json:"generationtime_ms"`
	UtcOffsetSeconds     int         `json:"utc_offset_seconds"`
	Timezone             string      `json:"timezone"`
	TimezoneAbbreviation string      `json:"timezone_abbreviation"`
	Elevation            float64     `json:"elevation"`
	HourlyUnits          HourlyUnits `json:"hourly_units"`
	Hourly               HourlyData  `json:"hourly"`
}

type HourlyUnits struct {
	Time             string `json:"time"`
	Temperature      string `json:"temperature_2m"`
	RelativeHumidity string `json:"relative_humidity_2m"`
}

type HourlyData struct {
	Time             []string  `json:"time"`
	Temperature      []float64 `json:"temperature_2m"`
	RelativeHumidity []int     `json:"relative_humidity_2m"`
}

type WeatherItem struct {
	Time        time.Time
	Temperature float64
	Humidity    int
}
