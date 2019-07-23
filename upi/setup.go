package main

import (
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"

	yaml "gopkg.in/yaml.v2"
	v1 "k8s.io/api/core/v1"
	v1meta "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func main() {
	argsWithoutProg := os.Args[1:]

	// TODO: validate
	yamlFilesPath := argsWithoutProg[0]

	err := filepath.Walk(yamlFilesPath, func(path string, info os.FileInfo, err error) error {
		if !info.IsDir() {
			bytes, err := ioutil.ReadFile(path)

			if err != nil {
				return err
			}

			var base v1meta.TypeMeta

			err = yaml.Unmarshal(bytes, &base)

			if err != nil {
				return err
			}

			fmt.Println(base.Kind)

			// Lots TODO here
			switch base.Kind {
			case "Secret":
				fmt.Println("Found 'Secret'")

				var secret v1.Secret
				err = yaml.Unmarshal(bytes, &secret)

				if err != nil {
					return err
				}

				fmt.Printf("Secret stuff: %s, %s\n", secret.StringData["username"], secret.StringData["password"])
			}
		}

		return nil
	})

	if err != nil {
		fmt.Println("Error: ", err)
	}
}
