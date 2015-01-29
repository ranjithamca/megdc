/*
** Copyright [2012-2014] [Megam Systems]
**
** Licensed under the Apache License, Version 2.0 (the "License");
** you may not use this file except in compliance with the License.
** You may obtain a copy of the License at
**
** http://www.apache.org/licenses/LICENSE-2.0
**
** Unless required by applicable law or agreed to in writing, software
** distributed under the License is distributed on an "AS IS" BASIS,
** WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
** See the License for the specific language governing permissions and
** limitations under the License.
 */

package servers

import (
	"errors"
	"fmt"
	"github.com/megamsys/cloudinabox/app"
	"github.com/megamsys/cloudinabox/models/orm"
	"net/http"
)

func InstallServers(serverName string) error {
	var err error
	switch serverName {
	case "MEGAM":
		err = app.MegamInstall()
		if err != nil {
			fmt.Printf("Error: Install error for [%s]", serverName)
			fmt.Println(err)
			return err
		}
	case "COBBLER":
		err = app.CobblerInstall()
		if err != nil {
			fmt.Printf("Error: Install error for [%s]", serverName)
			fmt.Println(err)
			return err
		}
	case "OPENNEBULA":
		err = app.NebulaInstall()
		if err != nil {
			fmt.Printf("Error: Install error for [%s]", serverName)
			fmt.Println(err)
			return err
		}
	case "OPENNEBULAHOST":
		err = app.OpenNebulaHostMasterInstall()
		if err != nil {
			fmt.Printf("Error: Install error for [%s]", serverName)
			fmt.Println(err)
			return err
		}
	case "NODEINSTALL":
		err = app.OpenNebulaHostNodeInstall()
		if err != nil {
			fmt.Printf("Error: Install error for [%s]", serverName)
			fmt.Println(err)
			return err
		}	
     case "HAINSTALL":
		err = app.HANodeInstall()
		if err != nil {
			fmt.Printf("Error: Install error for [%s]", serverName)
			fmt.Println(err)
			return err
		}	
	}
	return nil
}

func InstallNode(nodeip string, nodetype string, name string) error {
	if nodetype == "COMPUTE" {
	url := "http://" + nodeip + ":8078/servernodes/nodes/install"
	res, err := http.Get(url)
	if err != nil {
		return err
	} else {
		if res.StatusCode > 299 {
			return errors.New(res.Status)
		} else {
			err = app.SCPSSHInstall()
			return err
		}
	 }
	} else {
		url := "http://" + nodeip + ":8078/servernodes/ha/" + name + "/install"
	    res, err := http.Get(url)
	    if err != nil {
		    return err
	    } else {
		 if res.StatusCode > 299 {
			return errors.New(res.Status)
		} else {
			return nil
		}
	  }
	}
}

func InstallProxy(haserver *orm.HAServers, Stype string) error {
	cib := &app.CIB{}
	if Stype == "MASTER" {
		cib = &app.CIB{LocalIP: haserver.NodeIP1, LocalHost: haserver.NodeHost1, LocalDisk: haserver.NodeDisk1, RemoteIP: haserver.NodeIP2, RemoteHost: haserver.NodeHost2, RemoteDisk: haserver.NodeDisk2, Master: true}
	} else {
		cib = &app.CIB{LocalIP: haserver.NodeIP2, LocalHost: haserver.NodeHost2, LocalDisk: haserver.NodeDisk2, RemoteIP: haserver.NodeIP1, RemoteHost: haserver.NodeHost1, RemoteDisk: haserver.NodeDisk1, Master: false}
	}
	err := app.HAProxyInstall(cib, Stype)
		if err != nil {
			fmt.Printf("Error: Install error for HAProxy")
			fmt.Println(err)
			return err
		}
   return nil			
}


