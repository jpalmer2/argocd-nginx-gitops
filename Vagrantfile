Vagrant.configure("2") do |config|
	servers=[
		{
			:hostname => "master",
			:box => "bento/ubuntu-24.04",
			:ip => "172.20.1.50",
		},{
            :hostname => "worker1",
            :box => "bento/ubuntu-24.04",
            :ip => "172.20.1.51",
		},{
			:hostname => "worker2",
            :box => "bento/ubuntu-24.04",
            :ip => "172.20.1.52",
		}
	]

	servers.each do |machine|
		config.vm.define machine[:hostname] do |node|
			node.vm.box = machine[:box]
			node.vm.hostname = machine[:hostname]
			node.vm.network :private_network, ip: machine[:ip]
			node.vbguest.auto_update = true
			node.vm.synced_folder "data/", "/home/vagrant/data"
			node.vm.provision "file", source: "./copiedfile.txt", destination: "/home/vagrant/copiedfile.txt"
			node.vm.provision "file", source: "./manifests/custom-resources-bpf.yaml", destination: "/home/vagrant/custom-resources-bpf.yaml"
			node.vm.provider :virtualbox do |vb|
				vb.customize ["modifyvm", :id, "--memory", 4096]
				vb.customize ["modifyvm", :id, "--cpus", 4]
			end
			node.vm.provision "shell", path: "scripts/cluster.sh"
			if machine[:hostname] == "master" then
				node.vm.provision "shell", path: "scripts/master.sh"
			else
				node.vm.provision "shell", path: "scripts/worker.sh"
			end
		end
	end
end
