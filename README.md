# Kubernetes quick start

```
curl https://raw.githubusercontent.com/fiksn/kubestart/master/start.sh | sh
```

## What does this thing do?

This a quite lame (but quick) way to initialize your work environment to use our internal Kubernetes cluster (like request a certificate and download latest kubectl). Until we hook up authentication to AD we need this. For external users there is probably no real need to read this except curiosity.

## Compatibility

I am testing this with MacOS 10.12.6 but it should work also on GNU/Linux.
There is a bunch of external utilites required: 
* curl
* jq 
* base64 
* cfssl

## Motivation

I'd put the stuff in our internal GitLab repository but somebody decided that we should not be able to mark repos as "Public".
So this will (inevitably) leak a few (minor) details about our internal infrastructure (and apparently you already know we have an internal GitLab and lots of "smart" ideas ;) ).

## Pipe to shell

Hopefully we are all well aware piping data from the internet to your shell is not the way to go. But as mentioned [here](https://medium.com/@ewindisch/curl-bash-a-victimless-crime-d6676eb607c9) 
as long as your read the code and the transfer is authenticated (over HTTPS) it shouldn't be that problematic.

## Background
This script basically just emulates [Manage TLS Certificates in a Cluster](https://kubernetes.io/docs/tasks/tls/managing-tls-in-a-cluster/) Kubernetes tutorial.
[csr.yaml](./csr.yaml) is a way to tell Kubernetes [RBAC](https://kubernetes.io/docs/admin/authorization/rbac/) to allow anonymous certificate signing requests. As evident from [TLS bootstrapping](https://kubernetes.io/docs/admin/kubelet-tls-bootstrapping/) you can basically use 

```
--cluster-signing-cert-file="/etc/kubernetes/ca/ca.pem" --cluster-signing-key-file="/etc/kubernetes/ca/ca.key" 
```

flags to **kube-controller-manager** to automatically sign CSRs. The file locations (from above) are the defaults and as soon as the files exist csrapproving controller will do its job. As a word of wisdom, you might be careful about your CA key as they could get easily compromised (so don't put the root CA of your PKI there).

Note that for each CSR an admin still has to manually approve it like:

```
kubectl certificate approve name
```

only afterwards the controller will sign. Besides the admin should of course also give proper permissions / create role bindings ([example](./binding.yaml)).
