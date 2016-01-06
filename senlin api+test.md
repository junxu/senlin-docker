# 目录 
* 测试项
* 部署
* profile API
* cluster API
* policy API
* webhook API

## 0. 测试项
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>序号</td><td>测试项</td><td>测试步骤</td><td>测试结果</td><td>Desciption</td>
</tr>
<tr>
<td>1</td><td>测试profile创建</td>
<td>创建一个nova.yaml文件</br>`senlin profile-create -s nova.yaml p-nova`</td>
<td>ok</td><td>nova.yaml文件见后面</td>
</tr>
<tr>
<td>2</td><td>测试profile删除</td>
<td>`senlin profile-delete p-nova`</td>
<td>ok</td><td></td>
</tr>
<tr>
<td>3</td><td>测试profile查看</td>
<td>`senlin profile-show p-nova`</td>
<td>ok</td><td></td>
</tr>
<tr>
<td>4</td><td>测试profile列表</td>
<td>`senlin profile-list`</td>
<td>ok</td><td></td>
</tr>
<td>5</td><td>测试cluster创建</td>
<td>创建一个nova.yaml文件</br>`senlin profile-create -s nova.yaml p-nova`</br>`senlin cluster-create -p p-nova -c 2 -n 2 -m 2 c1`</td>
<td>ok</td><td>nova.yaml文件见后面</td>
</tr>
<tr>
<td>6</td><td>测试cluster删除</td>
<td>`senlin cluster-delete c1`</td>
<td>ok</td><td></td>
</tr>
<tr>
<td>7</td><td>测试cluster查看</td>
<td>`senlin cluster-show c1`</td>
<td>ok</td><td></td>
</tr>
<tr>
<td>8</td><td>测试cluster列表</td>
<td>`senlin cluster-list`</td>
<td>ok</td><td></td>
</tr>
<tr>
<td>9</td><td>测试profile1创建cluster</td>
<td>`senlin profile-create -s nova.yaml p-nova`</br>`senlin cluster-create -p p-nova -c 2 -n 2 -m 2 c1`</td>
<td>ok</td><td>测试简单profile（本地虚拟机）的cluster创建，nova.yaml见下文</td>
</tr>
<tr>
<td>10</td><td>测试profile2创建虚拟机</td>
<td>`senlin profile-create -s nova_vol.yaml p-nova-vol`</br>`senlin cluster-create -p p-nova-vol -c 2 -n 2 -m 2 c2`</td>
<td>ok</td><td>主要测试带volume和volume类型的profile创建cluster，nova_vol.yaml见下文</td>
</tr>
</table>

nova.yaml文件如下，为yaml格式：

    type: os.nova.server
    version: 1.0
    properties:
      name: cirros_server
      flavor: m1.small
      adminPass: 654321
      image: 2ddc08c2-c8cd-4b52-9fe2-642fcf5d763d
      networks:
        - network: net1
      metadata: {key1: xujun1}
      block_device_mapping_v2:
        - volume_size: 20
          uuid: 2ddc08c2-c8cd-4b52-9fe2-642fcf5d763d
          source_type: image
          destination_type: local
          boot_index: 0
          delete_on_termination: True

nova_vol.yaml文件如下，为yaml格式：

    type: os.nova.server
    version: 1.0
    properties:
      name: cirros_server
      flavor: m1.small
      adminPass: 654321
      image: 2ddc08c2-c8cd-4b52-9fe2-642fcf5d763d
      networks:
        - network: net1
      metadata: {key1: xujun1}
      block_device_mapping_v2:
        - volume_size: 20
          uuid: 2ddc08c2-c8cd-4b52-9fe2-642fcf5d763d
          source_type: image
          destination_type: local
          boot_index: 0
          delete_on_termination: True
        - volume_size: 100
          source_type: volume
          destination_type: volume
          volume_type: "shdcluster1"
          device_name: vdb

## 1. 部署测试
南基的弹性伸缩服务计划部署在Docker镜像中（其他服务为kilo版本，以此解决可能存在的包冲突问题）。

### 1.1 生成senlin docker镜像
Dockerfile在[https://github.com/junxu/senlin-docker/](https://github.com/junxu/senlin-docker/)

步骤：

* Clone Dockerfile `git clone https://github.com/junxu/senlin-docker/`
* 生成image `cd senlin-docker && docker build -t senlin-base:2.0.3 .` 
* 保存镜像 `docker save -o senlin-base-2.0.3 senlin-base:2.0.3`

### 1.2 部署

* 数据库上操作


    CREATE DATABASE senlin;
    GRANT ALL PRIVILEGES ON senlin.* TO 'senlin'@'localhost' IDENTIFIED BY 'senlin_passwd';
    GRANT ALL PRIVILEGES ON senlin.* TO 'senlin'@'%' IDENTIFIED BY 'senlin_passwd';
  
* keystone上操作


    openstack user create --password-prompt senlin 
    openstack role add --project service --user senlin admin
    openstack service create --name senlin --description "Senlin Clustering Service " clustering 
    openstack endpoint create --region RegionOne --publicurl http://vip:8778 --adminurl http://vip:8778 --internalurl http://vip:8778 senlin 

* 在部署节点导入senlin镜像


    docker load -i senlin-base-2.0.3 //导入镜像
    mkdir -p /etc/senlin /var/log/senlin /var/cache/senlin
    useradd --user-group senlin
    chown -R senlin:senlin /etc/senlin /var/log/senlin /var/cache/senlin
    echo "senlin ALL = (root) NOPASSWD: ALL" > /etc/sudoers.d/senlin
 
/etc/senlin/api-paste.ini

    # senlin-api pipeline
    [pipeline:senlin-api]
    pipeline = request_id faultwrap ssl versionnegotiation webhook authtoken context trust apiv1app
    #pipeline = request_id faultwrap ssl versionnegotiation authtoken context apiv1app
    
    [app:apiv1app]
    paste.app_factory = senlin.common.wsgi:app_factory
    senlin.app_factory = senlin.api.openstack.v1:API
    
    # Middleware to set x-openstack-request-id in http response header
    [filter:request_id]
    paste.filter_factory = oslo_middleware.request_id:RequestId.factory
    
    [filter:faultwrap]
    paste.filter_factory = senlin.common.wsgi:filter_factory
    senlin.filter_factory = senlin.api.openstack:faultwrap_filter
    
    [filter:context]
    paste.filter_factory = senlin.common.wsgi:filter_factory
    senlin.filter_factory = senlin.api.openstack:contextmiddleware_filter
    
    [filter:ssl]
    paste.filter_factory = oslo_middleware.ssl:SSLMiddleware.factory
    
    [filter:versionnegotiation]
    paste.filter_factory = senlin.common.wsgi:filter_factory
    senlin.filter_factory = senlin.api.openstack:version_negotiation_filter
    
    [filter:trust]
    paste.filter_factory = senlin.common.wsgi:filter_factory
    senlin.filter_factory = senlin.api.openstack:trustmiddleware_filter
    
    [filter:webhook]
    paste.filter_factory = senlin.common.wsgi:filter_factory
    senlin.filter_factory = senlin.api.openstack:webhookmiddleware_filter

/etc/senlin/policy.json

    {
        "context_is_admin":  "role:admin",
        "deny_everybody": "!",
    
        "build_info:build_info": "",
        "profile_types:index": "",
        "profile_types:get": "",
        "policy_types:index": "",
        "policy_types:get": "",
        "clusters:index": "",
        "clusters:create": "",
        "clusters:delete": "",
        "clusters:get": "",
        "clusters:action": "",
        "clusters:update": "",
        "profiles:index": "",
        "profiles:create": "",
        "profiles:get": "",
        "profiles:delete": "",
        "profiles:update": "",
        "nodes:index": "",
        "nodes:create": "",
        "nodes:get": "",
        "nodes:action": "",
        "nodes:update": "",
        "nodes:delete": "",
        "policies:index": "",
        "policies:create": "",
        "policies:get": "",
        "policies:update": "",
        "policies:delete": "",
        "cluster_policies:index": "",
        "cluster_policies:attach": "",
        "cluster_policies:detach": "",
        "cluster_policies:update": "",
        "cluster_policies:get": "",
        "receivers:index": "",
        "receivers:create": "",
        "receivers:get": "",
        "receivers:delete": "",
        "actions:index": "",
        "actions:get": "",
        "events:index": "",
        "events:get": "",
        "webhooks:trigger": ""
    }
 
/etc/senlin/senlin.conf

    [DEFAULT]
    rpc_backend = rabbit
    logging_exception_prefix = %(color)s%(asctime)s.%(msecs)03d TRACE %(name)s ^[[01;35m%(instance)s^[[00m
    logging_debug_format_suffix = ^[[00;33mfrom (pid=%(process)d) %(funcName)s %(pathname)s:%(lineno)d^[[00m
    use_syslog = False
    region_name_for_services = RegionOne
    #auth_encryption_key = afae86058d2aa7be331efb3187d5ad5d
    debug = True
    verbose = True
    log_dir = /var/log/senlin
    
    [oslo_messaging_rabbit]
    rabbit_userid = stackrabbit
    rabbit_password = 123456
    rabbit_hosts = 10.133.6.80
    
    [senlin_api]
    bind_port = 8778
    
    [database]
    connection = mysql+pymysql://root:123456@10.133.6.80/senlin?charset=utf8
    #connection = mysql://senlin:123456@10.133.6.80/senlin?charset=utf8
    
    [keystone_authtoken]
    admin_tenant_name = service
    admin_password = 123456
    admin_user = senlin
    auth_uri = http://controller-1:35357/v3
    signing_dir = /var/cache/senlin
    identity_uri = http://controller-1:35357
    
    [authentication]
    service_project_name = service
    service_password = 123456
    service_username = senlin
    auth_url = http://controller-1:35357/v3
    
    [oslo_messaging_rabbit]
    rabbit_userid = openstack
    rabbit_password = 123456
    rabbit_hosts = controller-1:5672,controller-2:5672,controller-3:5672

    [webhook]
	host = localhost #senlin-api host or vip
	port = 8778      #senlin-api port

### 1.2 制作senlin service
#### 创建senlin-api和senlin-engine容器
> ##### 创建senlin-api容器
	docker create –name senlin-api --net=host -v /etc/senlin:/etc/senlin -v /var/log/senlin/:/var/log/senlin -v /var/lib/mysql/mysql.sock:/var/lib/mysql/mysql.sock -u senlin senlin-base:2.0.3 start.sh senlin-api
##### 创建senlin-engine容器
	docker create –name senlin-engine --net=host -v /etc/senlin:/etc/senlin -v /var/log/senlin/:/var/log/senlin -v /var/lib/mysql/mysql.sock:/var/lib/mysql/mysql.sock -u senlin senlin-base:2.0.3 start.sh senlin-engine
##### 注意
这里需要`/var/lib/mysql/mysql.sock:/var/lib/mysql/mysql.sock`，因为该环境的mysql只能本地连接。
所以在`senlin.conf`使用如下配置项

>	 connection = mysql://senlin:123456@localhost/senlin?charset=utf8
正式环境应该使用：

>	 connection = mysql+pymysql://senlin:123456@localhost/senlin?charset=utf8

#### 在`/usr/lib/systemd/system/`目录项创建对应unit文件
> ##### 创建openstack-senlin-api unit文件（openstack-senlin-api.service）
>
>	 [Unit]
>	 Description=OpenStack Senlin api Service
>	 After=syslog.target network.target docker
>
>	 [Service]
>	 ExecStart=/usr/bin/docker start -a senlin-api
>
>	 ExecStop=/usr/bin/docker stop -t 2 senlin-api
>
>	 [Install]
> 	 WantedBy=multi-user.target
> ##### 创建openstack-senlin-engine unit文件（openstack-senlin-engine.service）
>
>	 [Unit]
>	 Description=OpenStack Senlin engine Service
>	 After=syslog.target network.target docker
>
>	 [Service]
>	 ExecStart=/usr/bin/docker start -a senlin-engine
>
>	 ExecStop=/usr/bin/docker stop -t 2 senlin-engine
>
>	 [Install]
> 	 WantedBy=multi-user.target

### 1.3 测试service
测试命令

    systemctl start openstack-senlin-api
	systemctl stop openstack-senlin-api
	systemctl start openstack-senlin-engine
	systemctl stop openstack-senlin-engine
测试结果： ok


## 2. profile测试
这部分对应四期文档的伸缩组适用配置。伸缩组适用配置只能创建、删除和查看，不能更新。弹性伸缩组将以及适用配置创建虚拟机。

创建一个profile，仅仅是记录未来使用该profile的伸缩组生成虚拟机所有需要的配置信息，因此profile里面的信息对错与否（如镜像id不存在、网络id不存咋），profile api中不会检查。
### 2.1 创建API示例
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>POST</td>
<td>/v1/profiles</td>
<td>Create a profile</td>
</tr>
</table>

Req body主要填写spec，这个是虚拟机的具体配置。

Request body示例：

    {
    	"profile": {
    		"permission": "",
    		"spec": {
    			"version": 1.0,
    			"type": "os.nova.server",
    			"properties": {
    				"name": "cirros_server",
    				"adminPass": 654321,
    				"block_device_mapping_v2": [{
    					"source_type": "image",
    					"boot_index": 0,
    					"uuid": "2ddc08c2-c8cd-4b52-9fe2-642fcf5d763d",
    					"volume_size": 20,
    					"destination_type": "local",
    					"delete_on_termination": true
    				},
    				{
    					"volume_size": 100,
    					"source_type": "volume",
    					"destination_type": "volume",
    					"volume_type": "shdcluster1",
    					"device_name": "vdb"
    				}],
    				"image": "2ddc08c2-c8cd-4b52-9fe2-642fcf5d763d",
    				"metadata": {
    					"key1": "xujun1"
    				},
    				"flavor": "m1.small",
    				"networks": [{
    					"network": "net1"
    				}]
    			}
    		},
    		"name": "p-nova4",
    		"metadata": {
    			"key2": "xj2",
    			"key1": "xj1"
    		}
    	}
    }
Normal response codes：200

Response body示例：

    {
    	"profile": {
    		"created_at": "2016-01-06T06:32:20",
    		"domain": null,
    		"id": "395b2dc1-6ea1-4ed9-bfce-72732821d1c6",
    		"metadata": {
    			"key1": "xj1",
    			"key2": "xj2"
    		},
    		"name": "p-nova4",
    		"permission": "",
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"spec": {
    			"properties": {
    				"adminPass": 654321,
    				"block_device_mapping_v2": [{
    					"boot_index": 0,
    					"delete_on_termination": true,
    					"destination_type": "local",
    					"source_type": "image",
    					"uuid": "2ddc08c2-c8cd-4b52-9fe2-642fcf5d763d",
    					"volume_size": 20
    				},
    				{
    					"destination_type": "volume",
    					"device_name": "vdb",
    					"source_type": "volume",
    					"volume_size": 100,
    					"volume_type": "shdcluster1"
    				}],
    				"flavor": "m1.small",
    				"image": "2ddc08c2-c8cd-4b52-9fe2-642fcf5d763d",
    				"metadata": {
    					"key1": "xujun1"
    				},
    				"name": "cirros_server",
    				"networks": [{
    					"network": "net1"
    				}]
    			},
    			"type": "os.nova.server",
    			"version": 1.0
    		},
    		"type": "os.nova.server-1.0",
    		"updated_at": null,
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	}
    }

### 2.2 删除
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>DELETE</td>
<td>/v1/profiles/{profile_id}</td>
<td>Delete a profile</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Name</td>
<td>Type</td>
<td>Desciption</td>
</tr>
<tr>
<td>{profile_id}</td>
<td>UUID</td>
<td>UUID of the profile</td>
</tr>
</table>

注意： 当一个profile被一个cluster使用时，删除不了profile.

Request body示例：None

Normal response codes：204 

Response body示例：None
### 2.3 查看
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>GET</td>
<td>/v1/profiles/{profile_id}</td>
<td>Show details for a profile</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Name</td>
<td>Type</td>
<td>Desciption</td>
</tr>
<tr>
<td>{profile_id}</td>
<td>UUID</td>
<td>UUID of the profile</td>
</tr>
</table>

Request body示例：None

Normal response codes：200

Response body示例：

    {
    	"profile": {
    		"created_at": "2016-01-06T05:58:37",
    		"domain": null,
    		"id": "5565fbbf-7181-48ee-a724-9ddb726f6986",
    		"metadata": {
    			
    		},
    		"name": "p-nova",
    		"permission": "",
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"spec": {
    			"properties": {
    				"adminPass": 654321,
    				"block_device_mapping_v2": [{
    					"boot_index": 0,
    					"delete_on_termination": true,
    					"destination_type": "local",
    					"source_type": "image",
    					"uuid": "2ddc08c2-c8cd-4b52-9fe2-642fcf5d763d",
    					"volume_size": 20
    				},
    				{
    					"destination_type": "volume",
    					"device_name": "vdb",
    					"source_type": "volume",
    					"volume_size": 100,
    					"volume_type": "shdcluster1"
    				}],
    				"flavor": "m1.small",
    				"image": "2ddc08c2-c8cd-4b52-9fe2-642fcf5d763d",
    				"metadata": {
    					"key1": "xujun1"
    				},
    				"name": "cirros_server",
    				"networks": [{
    					"network": "net1"
    				}]
    			},
    			"type": "os.nova.server",
    			"version": 1.0
    		},
    		"type": "os.nova.server-1.0",
    		"updated_at": null,
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	}
    }
### 2.4 列表
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>GET</td>
<td>/v1/profiles{?limit,marker,name,type,metadata,permission,sort_key,sort_dir,name}</td>
<td>List all profiles</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Name</td>
<td>Type</td>
<td>Desciption</td>
</tr>
<tr>
<td>{profile_id}</td>
<td>UUID</td>
<td>UUID of the profile</td>
</tr>
<tr>
<td>limit</td>
<td>Int(Optional)</td>
<td>Requests a page size of items. Returns a number of items up to a limit value. Use the limitparameter to make an initial limited request and use the ID of the last-seen item from the response as the markerparameter value in a subsequent limited request.</td>
</tr>
<tr>
<td>marker</td>
<td>String(Optional)</td>
<td>The ID of the last-seen item. Use the limitparameter to make an initial limited request and use the ID of the last-seen item from the response as the markerparameter value in a subsequent limited request.</td>
</tr>
<tr>
<td>...</td>
<td>...</td>
<td>...</td>
</tr>
</table>

Request body示例：None

Normal response codes：200

Response body示例：

    {
    	"profiles": [{
    		"created_at": "2016-01-06T05:58:37",
    		"domain": null,
    		"id": "5565fbbf-7181-48ee-a724-9ddb726f6986",
    		"metadata": {
    			
    		},
    		"name": "p-nova",
    		"permission": "",
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"spec": {
    			"properties": {
    				"adminPass": 654321,
    				"block_device_mapping_v2": [{
    					"boot_index": 0,
    					"delete_on_termination": true,
    					"destination_type": "local",
    					"source_type": "image",
    					"uuid": "2ddc08c2-c8cd-4b52-9fe2-642fcf5d763d",
    					"volume_size": 20
    				},
    				{
    					"destination_type": "volume",
    					"device_name": "vdb",
    					"source_type": "volume",
    					"volume_size": 100,
    					"volume_type": "shdcluster1"
    				}],
    				"flavor": "m1.small",
    				"image": "2ddc08c2-c8cd-4b52-9fe2-642fcf5d763d",
    				"metadata": {
    					"key1": "xujun1"
    				},
    				"name": "cirros_server",
    				"networks": [{
    					"network": "net1"
    				}]
    			},
    			"type": "os.nova.server",
    			"version": 1.0
    		},
    		"type": "os.nova.server-1.0",
    		"updated_at": null,
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	},
    	{
    		"created_at": "2016-01-06T06:25:15",
    		"domain": null,
    		"id": "a7614b3b-ddde-4834-93b8-fc73647cd00a",
    		"metadata": {
    			
    		},
    		"name": "p-nova2",
    		"permission": "",
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"spec": {
    			"properties": {
    				"adminPass": 654321,
    				"block_device_mapping_v2": [{
    					"boot_index": 0,
    					"delete_on_termination": true,
    					"destination_type": "local",
    					"source_type": "image",
    					"uuid": "2ddc08c2-c8cd-4b52-9fe2-642fcf5d763d",
    					"volume_size": 20
    				},
    				{
    					"destination_type": "volume",
    					"device_name": "vdb",
    					"source_type": "volume",
    					"volume_size": 100,
    					"volume_type": "shdcluster1"
    				}],
    				"flavor": "m1.small",
    				"image": "2ddc08c2-c8cd-4b52-9fe2-642fcf5d763d",
    				"metadata": {
    					"key1": "xujun1"
    				},
    				"name": "cirros_server",
    				"networks": [{
    					"network": "net1"
    				}]
    			},
    			"type": "os.nova.server",
    			"version": 1.0
    		},
    		"type": "os.nova.server-1.0",
    		"updated_at": null,
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	},
    	{
    		"created_at": "2016-01-06T06:32:08",
    		"domain": null,
    		"id": "3f1aee91-d0f2-4878-9c1a-302dde0e52a6",
    		"metadata": {
    			"key1": "xj1",
    			"key2": "xj2"
    		},
    		"name": "p-nova3",
    		"permission": "",
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"spec": {
    			"properties": {
    				"adminPass": 654321,
    				"block_device_mapping_v2": [{
    					"boot_index": 0,
    					"delete_on_termination": true,
    					"destination_type": "local",
    					"source_type": "image",
    					"uuid": "2ddc08c2-c8cd-4b52-9fe2-642fcf5d763d",
    					"volume_size": 20
    				},
    				{
    					"destination_type": "volume",
    					"device_name": "vdb",
    					"source_type": "volume",
    					"volume_size": 100,
    					"volume_type": "shdcluster1"
    				}],
    				"flavor": "m1.small",
    				"image": "2ddc08c2-c8cd-4b52-9fe2-642fcf5d763d",
    				"metadata": {
    					"key1": "xujun1"
    				},
    				"name": "cirros_server",
    				"networks": [{
    					"network": "net1"
    				}]
    			},
    			"type": "os.nova.server",
    			"version": 1.0
    		},
    		"type": "os.nova.server-1.0",
    		"updated_at": null,
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	}]
    }


## 3. cluster测试
### 3.1 创建API示例
创建操作是一个异步操作。
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>POST</td>
<td>/v1/clusters</td>
<td>Create a cluster</td>
</tr>
</table>


Request body示例：

    {
    	"cluster": {
    		"name": "c-no-vol",
    		"parent": null,
    		"profile_id": "f459dbe4-68aa-48ae-b22d-5fcfafccb567",
    		"min_size": "2",
    		"desired_capacity": "2",
    		"timeout": null,
    		"max_size": "5",
    		"metadata": {
    			
    		}
    	}
    }
Normal response codes：202

Response body示例：

    {
    	"cluster": {
    		"created_at": null,
    		"data": {
    			
    		},
    		"desired_capacity": 2,
    		"domain": null,
    		"id": "71b6255f-800f-4900-a9fc-2ffea071a840",
    		"init_at": "2016-01-06T07:15:46",
    		"max_size": 5,
    		"metadata": {
    			
    		},
    		"min_size": 2,
    		"name": "c-no-vol",
    		"nodes": [],
    		"parent": null,
    		"policies": [],
    		"profile_id": "f459dbe4-68aa-48ae-b22d-5fcfafccb567",
    		"profile_name": "p-no-volume",
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"status": "INIT",
    		"status_reason": "Initializing",
    		"timeout": 3600,
    		"updated_at": null,
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	}
    }

### 3.2 查看API示例
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>GET</td>
<td>/v1/clusters/{cluster_id}</td>
<td>Show details for a cluster</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Name</td>
<td>Type</td>
<td>Desciption</td>
</tr>
<tr>
<td>{cluster_id}</td>
<td>UUID</td>
<td>UUID of the cluster</td>
</tr>
</table>

Request body示例：None

Normal response codes：200

Response body示例：

    {
    	"cluster": {
    		"created_at": "2016-01-06T07:16:32",
    		"data": {
    			
    		},
    		"desired_capacity": 2,
    		"domain": null,
    		"id": "71b6255f-800f-4900-a9fc-2ffea071a840",
    		"init_at": "2016-01-06T07:15:46",
    		"max_size": 5,
    		"metadata": {
    			
    		},
    		"min_size": 2,
    		"name": "c-no-vol",
    		"nodes": ["c0fbeb92-46a0-47a6-83ca-0cbcfa5664c1",
    		"c4c0b694-8db4-4eac-9141-c9adac43850c"],
    		"parent": null,
    		"policies": [],
    		"profile_id": "f459dbe4-68aa-48ae-b22d-5fcfafccb567",
    		"profile_name": "p-no-volume",
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"status": "ACTIVE",
    		"status_reason": "Cluster creation succeeded.",
    		"timeout": 3600,
    		"updated_at": null,
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	}
    }

### 3.3 列表API示例
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>GET</td>
<td>/v1/clusters/{?limit,marker,name,status,show_nested,sort_key,sort_dir,global_project}</td>
<td>Show details for a cluster</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Name</td>
<td>Type</td>
<td>Desciption</td>
</tr>
<tr>
<td>{profile_id}</td>
<td>UUID</td>
<td>UUID of the profile</td>
</tr>
<tr>
<td>limit</td>
<td>Int(Optional)</td>
<td>Requests a page size of items. Returns a number of items up to a limit value. Use the limitparameter to make an initial limited request and use the ID of the last-seen item from the response as the markerparameter value in a subsequent limited request.</td>
</tr>
<tr>
<td>marker</td>
<td>String(Optional)</td>
<td>The ID of the last-seen item. Use the limitparameter to make an initial limited request and use the ID of the last-seen item from the response as the markerparameter value in a subsequent limited request.</td>
</tr>
<tr>
<td>...</td>
<td>...</td>
<td>...</td>
</tr>
</table>

Request body示例：None

Normal response codes：200

Response body示例：

    {
    	"clusters": [{
    		"created_at": "2016-01-06T07:16:32",
    		"data": {
    			
    		},
    		"desired_capacity": 2,
    		"domain": null,
    		"id": "71b6255f-800f-4900-a9fc-2ffea071a840",
    		"init_at": "2016-01-06T07:15:46",
    		"max_size": 5,
    		"metadata": {
    			
    		},
    		"min_size": 2,
    		"name": "c-no-vol",
    		"nodes": ["c0fbeb92-46a0-47a6-83ca-0cbcfa5664c1",
    		"c4c0b694-8db4-4eac-9141-c9adac43850c"],
    		"parent": null,
    		"policies": [],
    		"profile_id": "f459dbe4-68aa-48ae-b22d-5fcfafccb567",
    		"profile_name": "p-no-volume",
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"status": "ACTIVE",
    		"status_reason": "Cluster creation succeeded.",
    		"timeout": 3600,
    		"updated_at": null,
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	},
    	{
    		"created_at": "2016-01-06T07:42:37",
    		"data": {
    			
    		},
    		"desired_capacity": 2,
    		"domain": null,
    		"id": "1abc770d-679d-4462-ab4b-e2076699d91b",
    		"init_at": "2016-01-06T07:38:33",
    		"max_size": 5,
    		"metadata": {
    			
    		},
    		"min_size": 2,
    		"name": "c-nova",
    		"nodes": ["79f0731f-7422-4a12-9cca-a8d78ba25e92",
    		"d5979ac3-6d92-4418-8e6d-ee4ab3096908"],
    		"parent": null,
    		"policies": [],
    		"profile_id": "5565fbbf-7181-48ee-a724-9ddb726f6986",
    		"profile_name": "p-nova",
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"status": "ACTIVE",
    		"status_reason": "Cluster creation succeeded.",
    		"timeout": 3600,
    		"updated_at": null,
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	}]
    }

### 3.4 删除API示例
删除也是异步操作
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>DELETE</td>
<td>/v1/clusters/{cluster_id}</td>
<td>Delete a cluster</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Name</td>
<td>Type</td>
<td>Desciption</td>
</tr>
<tr>
<td>{cluster_id}</td>
<td>UUID</td>
<td>UUID of the cluster</td>
</tr>
</table>

Request body示例：None

Normal response codes：202

Response body示例： None

### 3.5 更新API示例
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>GET</td>
<td>/v1/clusters/cluster_id}</td>
<td>Show details for a cluster</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Name</td>
<td>Type</td>
<td>Desciption</td>
</tr>
<tr>
<td>{cluster_id}</td>
<td>UUID</td>
<td>UUID of the cluster</td>
</tr>
</table>

Request body示例：None

Normal response codes：200

Response body示例：


## 4. policy测试
## 5. webhook测试

