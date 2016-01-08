# 目录 
* 测试项
* 部署
* profile API
* cluster API
* policy API
* receiver API
* webhook API
* event API
* action API
* node API

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

## 1. 部署
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


## 2. profile API
这部分对应四期文档的伸缩组适用配置。伸缩组适用配置只能创建、删除和查看，不能更新。弹性伸缩组将以及适用配置创建虚拟机。

创建一个profile，仅仅是记录未来使用该profile的伸缩组生成虚拟机所有需要的配置信息，因此profile里面的信息对错与否（如镜像id不存在、网络id不存咋），profile api中不会检查。
### 2.1 profile创建API示例
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

### 2.2 profile删除
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
### 2.3 profile查看
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
### 2.4 profile列表
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
<tr><td>Name</td><td>Type</td><td>Desciption</td></tr>
<tr><td>name</td><td>string(optional)</td><td></td></tr>
<tr><td>type</td><td>string(optional)</td><td></td></tr>
<tr><td>permission</td><td>string(optional)</td><td></td></tr>
<tr><td>metadata</td><td>string(optional)</td><td></td></tr>
<tr><td>limit</td><td>integer(optional)</td><td></td></tr>
<tr><td>marker</td><td>string(optional)</td><td></td></tr>
<tr><td>sort_dir</td><td>string(optional)</td><td></td></tr>
<tr><td>sort_keys</td><td>list(optional)</td><td></td></tr>
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


## 3. cluster API
### 3.1 cluster创建API示例
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

### 3.2 cluster查看API示例
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

### 3.3 cluster列表API示例
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
<tr><td>Name</td><td>Type</td><td>Desciption</td></tr>
<tr><td>name</td><td>string(optional)</td><td></td></tr>
<tr><td>status</td><td>string(optional)</td><td></td></tr>
<tr><td>level</td><td>string(optional)</td><td></td></tr>
<tr><td>cooldown</td><td>string(optional)</td><td></td></tr>
<tr><td>limit</td><td>integer(optional)</td><td></td></tr>
<tr><td>marker</td><td>string(optional)</td><td></td></tr>
<tr><td>sort_dir</td><td>string(optional)</td><td></td></tr>
<tr><td>sort_keys</td><td>list(optional)</td><td></td></tr>
<tr><td>show_nested</td><td>boolean(optional)</td><td></td></tr>
<tr><td>global_project</td><td>boolean(optional)</td><td></td></tr>
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

### 3.4 cluster删除API示例
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

### 3.5 cluster更新API示例
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>PATCH</td>
<td>/v1/clusters/{cluster_id}</td>
<td>update a cluster</td>
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

Request body示例：

    {
    	"cluster": {
    		"parent": null,
    		"profile_id": "p-no-volume",
    		"name": null,
    		"timeout": null,
    		"metadata": {
    			
    		}
    	}
    }

Normal response codes：202

Response body示例：

    {
    	"cluster": {
    		"created_at": "2016-01-07T13:02:25",
    		"data": {
    			
    		},
    		"desired_capacity": 1,
    		"domain": null,
    		"id": "62382ad1-c223-4fc8-bc59-c16e575f0749",
    		"init_at": "2016-01-07T13:02:10",
    		"max_size": 5,
    		"metadata": {
    			
    		},
    		"min_size": 1,
    		"name": "c-nova-no-vol",
    		"nodes": ["177e53dd-7675-4150-a483-c4b482337062"],
    		"parent": null,
    		"policies": [],
    		"profile_id": "2a2e8ec6-e676-429f-9646-653545b1fdef",
    		"profile_name": "p-no-volume2",
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"status": "ACTIVE",
    		"status_reason": "Cluster creation succeeded.",
    		"timeout": 3600,
    		"updated_at": null,
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	}
    }

### 3.6 cluster policy list API
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>GET</td>
<td>/v1/clusters/{cluster_id}/policies</td>
<td>list all policies of the cluster</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr><td>Name</td><td>Type</td><td>Desciption</td></tr>
<tr><td>priority</td><td>int(optional)</td><td></td></tr>
<tr><td>level</td><td>int(optional)</td><td></td></tr>
<tr><td>cooldown</td><td>int(optional)</td><td></td></tr>
<tr><td>enabled</td><td>boolean(optional)</td><td></td></tr>
<tr><td>sort_dir</td><td>string(optional)</td><td></td></tr>
<tr><td>sort_keys</td><td>list(optional)</td><td></td></tr>
</table>


Request body示例：None

Normal response codes：200

Response body示例：

    {
    	"cluster_policies": [{
    		"cluster_id": "1abc770d-679d-4462-ab4b-e2076699d91b",
    		"cluster_name": "c-nova",
    		"cooldown": 300,
    		"data": null,
    		"enabled": true,
    		"id": "fec07bf5-0c6f-4f77-8515-a400cc4d95b8",
    		"last_op": "2016-01-07T12:19:45.000000",
    		"level": 0,
    		"policy_id": "e166d22a-bde4-44cf-81ab-561a080649f7",
    		"policy_name": "scale_in_policy",
    		"policy_type": "senlin.policy.scaling-1.0",
    		"priority": 50
    	},
    	{
    		"cluster_id": "1abc770d-679d-4462-ab4b-e2076699d91b",
    		"cluster_name": "c-nova",
    		"cooldown": 10,
    		"data": null,
    		"enabled": true,
    		"id": "e826a752-7a6e-443b-8a2e-4023497b8c4a",
    		"last_op": "2016-01-07T12:19:45.000000",
    		"level": 10,
    		"policy_id": "5ee84f3c-fd16-458e-bbfe-bca1aa880723",
    		"policy_name": "delete_policy",
    		"policy_type": "senlin.policy.deletion-1.0",
    		"priority": 50
    	}]
    }

### 3.7 cluster policy show  API
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>GET</td>
<td>/v1/clusters/{cluster_id}/policies/{policy_id}</td>
<td>show details for apolicy for a cluster</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr><td>Name</td><td>Type</td><td>Desciption</td></tr>
<tr><td>{cluster_id}</td><td>UUID</td><td>The uuid of the cluster</td></tr>
<tr><td>{policy_id}</td><td>UUID</td><td>the uuid of the policy</td></tr>
</table>

Request body示例：None

Normal response codes：200

Response body示例： 

    {
    	"cluster_policy": {
    		"cluster_id": "1abc770d-679d-4462-ab4b-e2076699d91b",
    		"cluster_name": "c-nova",
    		"cooldown": 10,
    		"data": null,
    		"enabled": true,
    		"id": "e826a752-7a6e-443b-8a2e-4023497b8c4a",
    		"last_op": "2016-01-07T12:19:45.000000",
    		"level": 10,
    		"policy_id": "5ee84f3c-fd16-458e-bbfe-bca1aa880723",
    		"policy_name": "delete_policy",
    		"policy_type": "senlin.policy.deletion-1.0",
    		"priority": 50
    	}
    }


### 3.8 cluster action API
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>POST</td>
<td>/v1/clusters/{cluster_id}/actions</td>
<td>Trigger an action on a cluster</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr><td>Name</td><td>Type</td><td>Desciption</td></tr>
<tr><td>{cluster_id}</td><td>UUID</td><td>The uuid of the cluster</td></tr>
</table>

cluster policy attach
>Request body示例：
>
>     {
>   	"policy_attach": {
>   		"priority": 50,
>   		"level": null,
>   		"cooldown": "300",
>   		"enabled": true,
>   		"policy_id": "e166d22a"
>   	}
>     }
>    
>Normal response codes：202
>
>Response body示例： 
>
>     {"action": "32058d5f-c316-4052-8c5f-a75ea62afb71"}

cluster policy detach
>Request body示例：
>
>     {"policy_detach": {"policy_id": "scale_in_policy"}}

>Normal response codes：202
>
>Response body示例： 
>
>     {"action": "d3357623-f5cd-44ff-aaf9-723a3d4441f4"}



cluster node add
>Request body示例：
>
>     {"add_nodes": {"nodes": ["test-node"]}}
>
>Normal response codes：202
>
>Response body示例： 
>  
>     {"action": "b1711e2a-228f-4ee5-abb0-ff0e0ff67893"}

cluster node del
>Request body示例：
>
>     {"del_nodes": {"nodes": ["test-node"]}}
>Normal response codes：202
>
>Response body示例： 
>
>     {"action": "de39e78b-e544-4e5a-9fd3-896d5091fd43"}

cluster scale out
>Request body示例：
>
>      {"scale_out": {"count": "1"}}
>Normal response codes：202
>
>Response body示例： 
>
>      {"action": "de39e78b-e544-4e5a-9fd3-896d5091fd43"}

cluster scale int
>Request body示例：
>
>      {"scale_in": {"count": "1"}}
>Normal response codes：202
>
>Response body示例： 
>
>      {"action": "de39e78b-e544-4e5a-9fd3-896d5091fd43"}

cluster scale resize
>Request body示例：
>
>     {
>    	"resize": {
>    		"min_step": null,
>    		"adjustment_type": "EXACT_CAPACITY",
>    		"number": 1,
>    		"min_size": 1,
>    		"strict": false,
>    		"max_size": null
>    	}
>     }
>    
>Normal response codes：202
>
>Response body示例： 
>
>     {"action": "de39e78b-e544-4e5a-9fd3-896d5091fd43"}



## 4. policy API
### 4.1 policy创建API示例
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>CREATE</td>
<td>/v1/policies</td>
<td>Create a policy</td>
</tr>
</table>

Request body示例(Delete policy)：

    {
    	"policy": {
    		"cooldown": "10",
    		"spec": {
    			"version": 1.0,
    			"type": "senlin.policy.deletion",
    			"properties": {
    				"criteria": "OLDEST_FIRST"
    			}
    		},
    		"name": "delete_policy",
    		"level": "10"
    	}
    }
Normal response codes：201

Response body示例(Delete policy)： 

    {
    	"policy": {
    		"cooldown": 10,
    		"created_at": "2016-01-07T01:31:39",
    		"data": {
    			
    		},
    		"domain": null,
    		"id": "5ee84f3c-fd16-458e-bbfe-bca1aa880723",
    		"level": 10,
    		"name": "delete_policy",
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"spec": {
    			"properties": {
    				"criteria": "OLDEST_FIRST"
    			},
    			"type": "senlin.policy.deletion",
    			"version": 1.0
    		},
    		"type": "senlin.policy.deletion-1.0",
    		"updated_at": null,
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	}
    }

Request body示例(LB policy)：

Normal response codes：201

    {
    	"policy": {
    		"cooldown": 0,
    		"spec": {
    			"version": 1.0,
    			"type": "senlin.policy.lb_member_v1",
    			"properties": {
    				"protocol_port": 600,
    				"pool": "01127f1d-c7ac-45ad-877c-30b9f29855af"
    			}
    		},
    		"name": "lb_policy",
    		"level": 0
    	}
    }

Response body示例(Delete policy)： 

    {
    	"policy": {
    		"cooldown": 0,
    		"created_at": "2016-01-07T05:58:45",
    		"data": {
    			
    		},
    		"domain": null,
    		"id": "5cf989a3-54b7-4d1c-8f49-726f2d8fec18",
    		"level": 0,
    		"name": "lb_policy",
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"spec": {
    			"properties": {
    				"pool": "01127f1d-c7ac-45ad-877c-30b9f29855af",
    				"protocol_port": 600
    			},
    			"type": "senlin.policy.lb_member_v1",
    			"version": 1.0
    		},
    		"type": "senlin.policy.lb_member_v1-1.0",
    		"updated_at": null,
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	}
    }

Request body示例(scale-in policy)：

    {
    	"policy": {
    		"cooldown": 0,
    		"spec": {
    			"version": 1.0,
    			"type": "senlin.policy.scaling",
    			"properties": {
    				"adjustment": {
    					"type": "CHANGE_IN_CAPACITY",
    					"best_effort": true,
    					"number": 1
    				},
    				"event": "CLUSTER_SCALE_IN"
    			}
    		},
    		"name": "scale_in_policy",
    		"level": 0
    	}
    }
	
Normal response codes：201

Response body示例(scale-in policy)： 
adjustment的type可以是EXACT_CAPACITY, CHANGE_IN_CAPACITY, CHANGE_IN_PERCENTAGE之一

    {
    	"policy": {
    		"cooldown": 0,
    		"created_at": "2016-01-07T09:43:11",
    		"data": {
    			
    		},
    		"domain": null,
    		"id": "e166d22a-bde4-44cf-81ab-561a080649f7",
    		"level": 0,
    		"name": "scale_in_policy",
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"spec": {
    			"properties": {
    				"adjustment": {
    					"best_effort": true,
    					"number": 1,
    					"type": "CHANGE_IN_CAPACITY"
    				},
    				"event": "CLUSTER_SCALE_IN"
    			},
    			"type": "senlin.policy.scaling",
    			"version": 1.0
    		},
    		"type": "senlin.policy.scaling-1.0",
    		"updated_at": null,
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	}
    }
	
	
Request body示例(scale-out policy)：

    {
    	"policy": {
    		"cooldown": 0,
    		"spec": {
    			"version": 1.0,
    			"type": "senlin.policy.scaling",
    			"properties": {
    				"adjustment": {
    					"type": "CHANGE_IN_CAPACITY",
    					"best_effort": true,
    					"number": 1
    				},
    				"event": "CLUSTER_SCALE_IN"
    			}
    		},
    		"name": "scale_out_policy",
    		"level": 0
    	}
    }	
Normal response codes：201

Response body示例(scale-out policy)： 
adjustment的type可以是EXACT_CAPACITY, CHANGE_IN_CAPACITY, CHANGE_IN_PERCENTAGE之一

    {
    	"policy": {
    		"cooldown": 0,
    		"created_at": "2016-01-07T09:45:04",
    		"data": {
    			
    		},
    		"domain": null,
    		"id": "14466479-9f0f-466a-9f20-ea2dfc3a30a4",
    		"level": 0,
    		"name": "scale_out_policy",
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"spec": {
    			"properties": {
    				"adjustment": {
    					"best_effort": true,
    					"number": 1,
    					"type": "CHANGE_IN_CAPACITY"
    				},
    				"event": "CLUSTER_SCALE_IN"
    			},
    			"type": "senlin.policy.scaling",
    			"version": 1.0
    		},
    		"type": "senlin.policy.scaling-1.0",
    		"updated_at": null,
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	}
    }

### 4.2 policy查看API示例
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>GET</td>
<td>/v1/policies{policy_id}</td>
<td>Show details for a policy</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Name</td>
<td>Type</td>
<td>Desciption</td>
</tr>
<tr>
<td>{policy_id}</td>
<td>UUID</td>
<td>UUID of the policy</td>
</tr>
</table>

Request body示例：None

Normal response codes：200

Response body示例： 

    {
    	"policy": {
    		"cooldown": 10,
    		"created_at": "2016-01-07T01:31:39",
    		"data": {
    			
    		},
    		"domain": null,
    		"id": "5ee84f3c-fd16-458e-bbfe-bca1aa880723",
    		"level": 10,
    		"name": "delete_policy",
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"spec": {
    			"properties": {
    				"criteria": "OLDEST_FIRST"
    			},
    			"type": "senlin.policy.deletion",
    			"version": 1.0
    		},
    		"type": "senlin.policy.deletion-1.0",
    		"updated_at": null,
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	}
    }
### 4.3 policy列表API示例
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>GET</td>
<td>/v1/policies</td>
<td>List all policies</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr><td>Name</td><td>Type</td><td>Desciption</td></tr>
<tr><td>name</td><td>string(optional)</td><td></td></tr>
<tr><td>type</td><td>string(optional)</td><td></td></tr>
<tr><td>level</td><td>string(optional)</td><td></td></tr>
<tr><td>cooldown</td><td>string(optional)</td><td></td></tr>
<tr><td>limit</td><td>integer(optional)</td><td></td></tr>
<tr><td>marker</td><td>string(optional)</td><td></td></tr>
<tr><td>sort_dir</td><td>string(optional)</td><td></td></tr>
<tr><td>sort_keys</td><td>list(optional)</td><td></td></tr>
</table>

Request body示例：None
Normal response codes：200
Response body示例：

    {
    	"policies": [{
    		"cooldown": 10,
    		"created_at": "2016-01-07T01:31:39",
    		"data": {
    			
    		},
    		"domain": null,
    		"id": "5ee84f3c-fd16-458e-bbfe-bca1aa880723",
    		"level": 10,
    		"name": "delete_policy",
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"spec": {
    			"properties": {
    				"criteria": "OLDEST_FIRST"
    			},
    			"type": "senlin.policy.deletion",
    			"version": 1.0
    		},
    		"type": "senlin.policy.deletion-1.0",
    		"updated_at": null,
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	},
    	{
    		"cooldown": 0,
    		"created_at": "2016-01-07T05:58:45",
    		"data": {
    			
    		},
    		"domain": null,
    		"id": "5cf989a3-54b7-4d1c-8f49-726f2d8fec18",
    		"level": 0,
    		"name": "lb_policy",
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"spec": {
    			"properties": {
    				"pool": "01127f1d-c7ac-45ad-877c-30b9f29855af",
    				"protocol_port": 600
    			},
    			"type": "senlin.policy.lb_member_v1",
    			"version": 1.0
    		},
    		"type": "senlin.policy.lb_member_v1-1.0",
    		"updated_at": null,
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	}]
    }
 
### 4.4 policy删除API示例
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>DELETE</td>
<td>/v1/policies/{policy_id}</td>
<td>Delete a policy</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Name</td>
<td>Type</td>
<td>Desciption</td>
</tr>
<tr>
<td>{policy_id}</td>
<td>UUID</td>
<td>UUID of the policy</td>
</tr>
</table>

Request body示例：None

Normal response codes：204

Response body示例：None

### 4.5 policy更新API示例
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>PATCH</td>
<td>/v1/policies/{policy_id}</td>
<td>Update a policy</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Name</td>
<td>Type</td>
<td>Desciption</td>
</tr>
<tr>
<td>{policy_id}</td>
<td>UUID</td>
<td>UUID of the policy</td>
</tr>
</table>

Request body示例：

    {
    	"policy": {
    		"cooldown": "100",
    		"name": "lb_policy3",
    		"level": "20"
    	}
    }
Normal response codes：200

Response body示例： 

    {
    	"policy": {
    		"cooldown": 100,
    		"created_at": "2016-01-07T06:08:15",
    		"data": {
    			
    		},
    		"domain": null,
    		"id": "439e3676-4d72-4969-8acd-738a57beaed6",
    		"level": 20,
    		"name": "lb_policy3",
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"spec": {
    			"properties": {
    				"pool": "01127f1d-c7ac-45ad-877c-30b9f29855af",
    				"protocol_port": 600
    			},
    			"type": "senlin.policy.lb_member_v1",
    			"version": 1.0
    		},
    		"type": "senlin.policy.lb_member_v1-1.0",
    		"updated_at": "2016-01-07T06:16:14",
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	}
    }

##5. receiver API
### 5.1 receiver创建API示例
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>POST</td>
<td>/v1/receivers</td>
<td>create a receiver</td>
</tr>
</table>

Request body示例：

    {
    	"receiver": {
    		"action": "CLUSTER_SCALE_OUT",
    		"type": "webhook",
    		"cluster_id": "c-nova",
    		"name": "webhook1",
    		"params": {
    			
    		}
    	}
    }

Response code: 201

Response body示例：

    {
    	"receiver": {
    		"action": "CLUSTER_SCALE_OUT",
    		"actor": {
    			"trust_id": ["e1183147e3174c3a844aa1f562ceff9b"]
    		},
    		"channel": {
    			"alarm_url": "http://controller-1:8778/v1/webhooks/e27a45fd-f1d2-4068-b165-32656a280f2d/trigger?V=1"
    		},
    		"cluster_id": "1abc770d-679d-4462-ab4b-e2076699d91b",
    		"created_at": "2016-01-08T01:02:22",
    		"domain": null,
    		"id": "e27a45fd-f1d2-4068-b165-32656a280f2d",
    		"name": "webhook1",
    		"params": {
    			
    		},
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"type": "webhook",
    		"updated_at": null,
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	}
    }

### 5.2 receiver列表API示例
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>GET</td>
<td>/v1/receivers</td>
<td>list all receivers</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr><td>Name</td><td>Type</td><td>Desciption</td></tr>
<tr><td>name</td><td>string(optional)</td><td></td></tr>
<tr><td>type</td><td>string(optional)</td><td></td></tr>
<tr><td>cluster_id</td><td>string(optional)</td><td></td></tr>
<tr><td>action</td><td>string(optional)</td><td></td></tr>
<tr><td>limit</td><td>integer(optional)</td><td></td></tr>
<tr><td>marker</td><td>string(optional)</td><td></td></tr>
<tr><td>sort_dir</td><td>string(optional)</td><td></td></tr>
<tr><td>sort_keys</td><td>list(optional)</td><td></td></tr>
<tr><td>global_project</td><td>boolean(optional)</td><td></td></tr>
</table>

Request body示例：None

Normal response codes：200

Response body示例：

    {
    	"receivers": [{
    		"action": "CLUSTER_SCALE_OUT",
    		"actor": {
    			"trust_id": ["e1183147e3174c3a844aa1f562ceff9b"]
    		},
    		"channel": {
    			"alarm_url": "http://controller-1:8778/v1/webhooks/e27a45fd-f1d2-4068-b165-32656a280f2d/trigger?V=1"
    		},
    		"cluster_id": "1abc770d-679d-4462-ab4b-e2076699d91b",
    		"created_at": "2016-01-08T01:02:22",
    		"domain": null,
    		"id": "e27a45fd-f1d2-4068-b165-32656a280f2d",
    		"name": "webhook1",
    		"params": {
    			
    		},
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"type": "webhook",
    		"updated_at": null,
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	}]
    }

### 5.3 receiver查看API示例

<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>GET</td>
<td>/v1/receivers/{receiver_id}</td>
<td>show detail of reveiver</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Name</td>
<td>Type</td>
<td>Desciption</td>
</tr>
<tr>
<td>{receiver_id}</td>
<td>UUID</td>
<td>UUID of the receiver</td>
</tr>
</table>

Request body示例：None

Normal response codes：200

Response body示例：

    {
    	"receiver": {
    		"action": "CLUSTER_SCALE_OUT",
    		"actor": {
    			"trust_id": ["e1183147e3174c3a844aa1f562ceff9b"]
    		},
    		"channel": {
    			"alarm_url": "http://controller-1:8778/v1/webhooks/e27a45fd-f1d2-4068-b165-32656a280f2d/trigger?V=1"
    		},
    		"cluster_id": "1abc770d-679d-4462-ab4b-e2076699d91b",
    		"created_at": "2016-01-08T01:02:22",
    		"domain": null,
    		"id": "e27a45fd-f1d2-4068-b165-32656a280f2d",
    		"name": "webhook1",
    		"params": {
    			
    		},
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"type": "webhook",
    		"updated_at": null,
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	}
    }

### 5.4 receiver删除API示例

<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>DELETE</td>
<td>/v1/receivers/{receiver_id}</td>
<td>create a receiver</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Name</td>
<td>Type</td>
<td>Desciption</td>
</tr>
<tr>
<td>{receiver_id}</td>
<td>UUID</td>
<td>UUID of the receiver</td>
</tr>
</table>

Request body示例：None

Normal response codes：204

Response body示例：None

##6. webhook API
直接POST请求该URL（不需要token），该URL是创建webhook类型的receiver时候返回的。


## 7 event API
OP应该不需要调用这边的API
### 7.1 event列表API
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>GET</td>
<td>/v1/events</td>
<td>list all events</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr><td>Name</td><td>Type</td><td>Desciption</td></tr>
<tr><td>obj_name</td><td>string(optional)</td><td></td></tr>
<tr><td>obj_type</td><td>string(optional)</td><td></td></tr>
<tr><td>obj_id</td><td>string(optional)</td><td></td></tr>
<tr><td>cluster_id</td><td>string(optional)</td><td></td></tr>
<tr><td>level</td><td>string(optional)</td><td></td></tr>
<tr><td>action</td><td>string(optional)</td><td></td></tr>
<tr><td>limit</td><td>integer(optional)</td><td></td></tr>
<tr><td>marker</td><td>string(optional)</td><td></td></tr>
<tr><td>sort_dir</td><td>string(optional)</td><td></td></tr>
<tr><td>sort_keys</td><td>list(optional)</td><td></td></tr>
<tr><td>global_project</td><td>boolean(optional)</td><td></td></tr>
</table>

Request body示例：None

Normal response codes：200

Response body示例：

### 7.2 event查看API
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>DELETE</td>
<td>/v1/events/{event_id}</td>
<td>show detail of a event</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Name</td>
<td>Type</td>
<td>Desciption</td>
</tr>
<tr>
<td>{event_id}</td>
<td>UUID</td>
<td>UUID of the event</td>
</tr>
</table>

Request body示例：None

Normal response codes：200

Response body示例：

    {
    	"event": {
    		"action": "NODE_DELETE",
    		"cluster_id": null,
    		"id": "fc3626cb-44f6-461c-b7b8-d36e2940393e",
    		"level": "20",
    		"metadata": {
    			
    		},
    		"obj_id": "2c197203-a06e-4594-a878-987511e1cfc6",
    		"obj_name": "node_delete_c4c0b694",
    		"obj_type": "NODEACTION",
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"status": "SUCCEEDED",
    		"status_reason": "Node deleted successfully.",
    		"timestamp": "2016-01-06T07:52:54",
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	}
    }
## 8 action API
OP应该不需要调用这边的API
### 8.1 action列表API
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>GET</td>
<td>/v1/actions</td>
<td>list all actions</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr><td>Name</td><td>Type</td><td>Desciption</td></tr>
<tr><td>status</td><td>string(optional)</td><td>status of node</td></tr>
<tr><td>name</td><td>string(optional)</td><td></td></tr>
<tr><td>target</td><td>string(optional)</td><td></td></tr>
<tr><td>action</td><td>string(optional)</td><td></td></tr>
<tr><td>limit</td><td>integer(optional)</td><td></td></tr>
<tr><td>marker</td><td>string(optional)</td><td></td></tr>
<tr><td>sort_dir</td><td>string(optional)</td><td></td></tr>
<tr><td>sort_keys</td><td>list(optional)</td><td></td></tr>
</table>

Request body示例：None

Normal response codes：200

Response body示例：

### 8.2 action查看API
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>DELETE</td>
<td>/v1/actions/{action_id}</td>
<td>show detail of a action</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Name</td>
<td>Type</td>
<td>Desciption</td>
</tr>
<tr>
<td>{action_id}</td>
<td>UUID</td>
<td>UUID of the action</td>
</tr>
</table>

Request body示例：None

Normal response codes：200

Response body示例：

    {
    	"action": {
    		"action": "CLUSTER_CREATE",
    		"cause": "RPC Request",
    		"context": {
    			"auth_token": null,
    			"auth_token_info": null,
    			"auth_url": null,
    			"domain": null,
    			"domain_name": null,
    			"is_admin": false,
    			"password": null,
    			"project": "d3d2f1bc367c493fa5649fd377440c8b",
    			"project_domain": null,
    			"project_domain_name": null,
    			"project_name": null,
    			"region_name": null,
    			"request_id": "req-310da91e-9e39-4915-87b4-08d1ceaa9720",
    			"roles": [],
    			"show_deleted": false,
    			"trusts": null,
    			"user": "2b03c065c9944ce389f0c387aab60cce",
    			"user_domain": null,
    			"user_domain_name": null,
    			"user_name": null
    		},
    		"created_at": "2016-01-06T07:38:33.000000",
    		"data": {
    			
    		},
    		"depended_by": [],
    		"depends_on": [],
    		"end_time": 1452066176.0,
    		"id": "145c583e-89e2-4661-903d-363ba623f0f0",
    		"inputs": {
    			
    		},
    		"interval": -1,
    		"name": "cluster_create_1abc770d",
    		"outputs": {
    			
    		},
    		"owner": null,
    		"start_time": 1452065920.0,
    		"status": "SUCCEEDED",
    		"status_reason": "Action completed successfully.",
    		"target": "1abc770d-679d-4462-ab4b-e2076699d91b",
    		"timeout": 3600,
    		"updated_at": null
    	}
    }

## 9 node API
### 9.1 node创建API
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>POST</td>
<td>/v1/nodes</td>
<td>create a node</td>
</tr>
</table>


Request body示例：

    {
    	"node": {
    		"role": null,
    		"name": "test-node2",
    		"tags": {
    			
    		},
    		"cluster_id": null,
    		"profile_id": "p-no-volume",
    		"metadata": {
    			
    		}
    	}
    }

Normal response codes：202

Response body示例：

    {
    	"node": {
    		"cluster_id": null,
    		"created_at": null,
    		"data": {
    			
    		},
    		"domain": null,
    		"id": "71b6e131-e32b-4e83-97f4-557677592891",
    		"index": -1,
    		"init_at": "2016-01-07T08:39:42",
    		"metadata": {
    			
    		},
    		"name": "test-node2",
    		"physical_id": "",
    		"profile_id": "f459dbe4-68aa-48ae-b22d-5fcfafccb567",
    		"profile_name": "p-no-volume",
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"role": null,
    		"status": "INIT",
    		"status_reason": "Initializing",
    		"updated_at": null,
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	}
    }
### 9.2 node查看API
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>GET</td>
<td>/v1/nodes/{node_id}</td>
<td>show detail of a node</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Name</td>
<td>Type</td>
<td>Desciption</td>
</tr>
<tr>
<td>{node_id}</td>
<td>UUID</td>
<td>UUID of the node</td>
</tr>
</table>

Request body示例：None

Normal response codes：200

Response body示例：

    {
    	"node": {
    		"cluster_id": null,
    		"created_at": "2016-01-07T08:41:15",
    		"data": {
    			
    		},
    		"details": {
    			
    		},
    		"domain": null,
    		"id": "71b6e131-e32b-4e83-97f4-557677592891",
    		"index": -1,
    		"init_at": "2016-01-07T08:39:42",
    		"metadata": {
    			
    		},
    		"name": "test-node2",
    		"physical_id": "5e132498-904c-470b-b073-ce2e4b396c33",
    		"profile_id": "f459dbe4-68aa-48ae-b22d-5fcfafccb567",
    		"profile_name": "p-no-volume",
    		"project": "d3d2f1bc367c493fa5649fd377440c8b",
    		"role": null,
    		"status": "ACTIVE",
    		"status_reason": "Creation succeeded",
    		"updated_at": null,
    		"user": "2b03c065c9944ce389f0c387aab60cce"
    	}
    }
### 9.3 node列表API
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>GET</td>
<td>/v1/nodes/{node_id}</td>
<td>list all nodes</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr><td>Name</td><td>Type</td><td>Desciption</td></tr>
<tr><td>status</td><td>string(optional)</td><td>status of node</td></tr>
<tr><td>name</td><td>string(optional)</td><td></td></tr>
<tr><td>cluster_id</td><td>string(optional)</td><td></td></tr>
<tr><td>limit</td><td>integer(optional)</td><td></td></tr>
<tr><td>marker</td><td>string(optional)</td><td></td></tr>
<tr><td>sort_dir</td><td>string(optional)</td><td></td></tr>
<tr><td>sort_keys</td><td>list(optional)</td><td></td></tr>
<tr><td>global_project</td><td>boolean(optional)</td><td></td></tr>
</table>

Request body示例：None

Normal response codes：200

Response body示例： 省略

### 9.4 node更新API
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>PATCH</td>
<td>/v1/nodes/{node_id}</td>
<td>update a node</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Name</td>
<td>Type</td>
<td>Desciption</td>
</tr>
<tr>
<td>{node_id}</td>
<td>UUID</td>
<td>UUID of the node</td>
</tr>
</table>

Request body示例：待更新

Normal response codes：200

Response body示例：待更新


### 9.5 node删除API
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>PATCH</td>
<td>/v1/nodes/{node_id}</td>
<td>delete a node</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Name</td>
<td>Type</td>
<td>Desciption</td>
</tr>
<tr>
<td>{node_id}</td>
<td>UUID</td>
<td>UUID of the node</td>
</tr>
</table>

Request body示例：None

Normal response codes：202

Response body示例：None

### 9.6 node action API
<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Method</td>
<td>URI</td>
<td>Desciption</td>
</tr>
<tr>
<td>DELETE</td>
<td>/v1/nodes/{node_id}/actions</td>
<td>node action</td>
</tr>
</table>

<table class="tale table-borderd table-striped table-condensed">
<tr>
<td>Name</td>
<td>Type</td>
<td>Desciption</td>
</tr>
<tr>
<td>{node_id}</td>
<td>UUID</td>
<td>UUID of the node</td>
</tr>
</table>

Join 示例
> Request body示例(node join)：
> 
>     {
>     	"join": {
>     		"cluster_id": "1abc770d"
>     	}
>     }
> Normal response codes：202
> 
> Response body示例(node join)：
> 
>     {"action": "c496348e-8290-43c3-8973-e57b029d60fe"}


Leave 示例	
> Request body示例(node leave)：
> 
>     {"leave": {}}
> 	
> Normal response codes：202
> 
> Response body示例(node leave)：
> 
>     {"action": "5801c7b2-c142-45e3-a976-bcbfeb2530ab"}
