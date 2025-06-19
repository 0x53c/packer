// pulumi/main.go

package main

import (
	"os/exec"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// K3dCluster represents our Kubernetes cluster
type K3dCluster struct {
	pulumi.CustomResourceState

	Name      pulumi.StringOutput `pulumi:"name"`
	ImagePath pulumi.StringOutput `pulumi:"imagePath"`
	Status    pulumi.StringOutput `pulumi:"status"`
	ApiPort   pulumi.IntOutput    `pulumi:"apiPort"`
}

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		conf := config.New(ctx, "")
		clusterName := conf.Get("clusterName")
		if clusterName == "" {
			clusterName = "helios-k3d"
		}

		imagePath := conf.Get("imagePath")
		if imagePath == "" {
			imagePath = "../output-k3d-cluster/k3d-cluster-latest.tar.gz"
		}

		orbProvider := pulumi.NewProviderResource("orbstack", "orbstack-provider", &pulumi.ProviderResourceArgs{})

		cluster, err := pulumi.NewCustomResource(ctx, clusterName, "orbstack:index:Machine", pulumi.Map{
			"name":      pulumi.String(clusterName),
			"imagePath": pulumi.String(imagePath),
			"memoryGB":  pulumi.Int(4),
			"cpuCount":  pulumi.Int(2),
		}, &pulumi.CustomResourceOptions{
			Provider: orbProvider,
			CustomTimeouts: &pulumi.CustomTimeouts{
				Create: "10m",
				Update: "5m",
				Delete: "5m",
			},
		})

		if err != nil {
			return err
		}

		ctx.Export("clusterName", cluster.ID())
		ctx.Export("kubeconfig", pulumi.All(cluster.ID()).ApplyT(func(args []interface{}) (string, error) {
			name := args[0].(string)
			cmd := exec.Command("orb", "machine", "ssh", name, "-c", "cat /home/core/.kube/config")
			output, err := cmd.Output()
			if err != nil {
				return "", err
			}
			return string(output), nil
		}).(pulumi.StringOutput))

		return nil
	})
}
