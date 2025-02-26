package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

//TIP <p>To run your code, right-click the code and select <b>Run</b>.</p> <p>Alternatively, click
// the <icon src="AllIcons.Actions.Execute"/> icon in the gutter and select the <b>Run</b> menu item from here.</p>

func main() {
	openMeteoModel := GetOpenMeteoData()

	dataToSave := Convert(openMeteoModel)

	uploadToDbBatch("spb1", dataToSave)
}

func Convert(model *OpenMeteoResponseModel) []WeatherItem {
	var result []WeatherItem
	fmt.Println("Converting...")
	for i := 0; i < len(model.Hourly.Time); i++ {
		newItem := WeatherItem{
			Time:        parseTime(model.Hourly.Time[i]),
			Temperature: model.Hourly.Temperature[i],
			Humidity:    model.Hourly.RelativeHumidity[i],
		}
		result = append(result, newItem)
	}

	return result
}

func parseTime(s string) time.Time {
	t, err := time.Parse("2006-01-02T15:04", s)
	if err != nil {
		fmt.Println(err)
	}
	return t
}

func GetOpenMeteoData() *OpenMeteoResponseModel {
	fmt.Println("Loading Open Meteo Data from API...")
	request, err := http.NewRequest(
		"GET",
		"https://archive-api.open-meteo.com/v1/archive"+
			"?latitude=60.071&longitude=30.445"+
			//"?latitude=52.52&longitude=13.41"+
			"&start_date=2023-07-01"+
			"&end_date=2024-07-02"+
			"&hourly=temperature_2m,relative_humidity_2m",
		nil,
	)
	if err != nil {
		fmt.Println(err)
	}

	httpClient := &http.Client{}

	response, err := httpClient.Do(request)

	if err != nil {
		fmt.Println(err)
	}

	contentType := response.Header.Get("Content-Type")
	fmt.Println(contentType)
	if contentType != "application/json" {
		body, _ := io.ReadAll(response.Body)

		//bodyString := string(body)
		//fmt.Println(bodyString)

		model := &OpenMeteoResponseModel{}
		err = json.Unmarshal(body, model)
		if err != nil {
			fmt.Println(err)
		}

		fmt.Println(fmt.Sprintf("Loaded rows: %d", len(model.Hourly.Time)))

		return model
	}

	return nil
}
