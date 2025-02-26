package main

import (
	"database/sql"
	"fmt"
	"strings"
	"time"

	_ "github.com/lib/pq"
)

const (
	host     = "192.168.5.25"
	port     = 5430
	user     = "user1"
	password = "user1"
	dbname   = "meteo"
)

func uploadToDbBatch(mName string, mItems []WeatherItem) {
	fmt.Println("Uploading...")
	psqlInfo := fmt.Sprintf(
		"host=%s port=%d user=%s password=%s dbname=%s sslmode=disable",
		host, port, user, password, dbname)

	db, err := sql.Open("postgres", psqlInfo)
	if err != nil {
		panic(err)
	}
	defer db.Close()

	clearStatement := `DELETE FROM meteo.model.weather_data where model_name = $1`
	_, err = db.Exec(clearStatement, mName)
	if err != nil {
		panic(err)
	}

	valueStrings := make([]string, 0, len(mItems))
	valueArgs := make([]interface{}, 0, len(mItems)*4)

	for i := 0; i < len(mItems); i++ {
		valueStrings = append(valueStrings, fmt.Sprintf("($%d, $%d, $%d, $%d)", i*4+1, i*4+2, i*4+3, i*4+4))
		valueArgs = append(valueArgs, mName)
		valueArgs = append(valueArgs, mItems[i].Time)
		valueArgs = append(valueArgs, mItems[i].Temperature)
		valueArgs = append(valueArgs, mItems[i].Humidity)
	}

	vString := strings.Join(valueStrings, ",")

	sqlStatement := fmt.Sprintf(
		"INSERT INTO meteo.model.weather_data (model_name, m_time, m_temperature, m_humidity) VALUES %s",
		vString)

	_, err = db.Exec(sqlStatement, valueArgs...)
	if err != nil {
		panic(err)
	}

	fmt.Println("Done")
}

func uploadToDb(mName string, mItems []WeatherItem) {
	fmt.Println("Uploading...")
	psqlInfo := fmt.Sprintf(
		"host=%s port=%d user=%s password=%s dbname=%s sslmode=disable",
		host, port, user, password, dbname)

	db, err := sql.Open("postgres", psqlInfo)
	if err != nil {
		panic(err)
	}
	defer db.Close()

	clearStatement := `DELETE FROM meteo.model.weather_data where model_name = $1`
	_, err = db.Query(clearStatement, mName)
	if err != nil {
		panic(err)
	}

	sqlStatement := `
		INSERT INTO meteo.model.weather_data (model_name, m_time, m_temperature, m_humidity)
		VALUES ($1, $2, $3, $4)`

	for i := 0; i < len(mItems); i++ {

		rows, err := db.Query(sqlStatement, mName, mItems[i].Time, mItems[i].Temperature, mItems[i].Humidity)
		if err != nil {
			panic(err)
		}

		err = rows.Close()
		if err != nil {
			fmt.Println(err)
		}
	}

	fmt.Println("Done")
}

func dbTest() {
	psqlInfo := fmt.Sprintf("host=%s port=%d user=%s "+
		"password=%s dbname=%s sslmode=disable",
		host, port, user, password, dbname)
	db, err := sql.Open("postgres", psqlInfo)
	if err != nil {
		panic(err)
	}
	defer db.Close()

	sqlStatement := `
		INSERT INTO meteo.model.weather_data (model_name, m_time, m_temperature, m_humidity)
		VALUES ($1, $2, $3, $4)`

	_, err = db.Query(sqlStatement, "test", time.Now(), 123.7, 35)
	if err != nil {
		panic(err)
	}
	fmt.Println("Done")
}
