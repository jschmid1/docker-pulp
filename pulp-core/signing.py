from pulpcore.app.models.content import AsciiArmoredDetachedSigningService
from pulp_deb.app.models import AptReleaseSigningService

NAME = "sign-metadata-v1"
script_path = "/opt/pulp/bin/sign-metadata"

# read an already exported public key
with open("/tmp/public.key") as key:
    with open("/tmp/public.fpr") as fpr:
        fingerprint = fpr.read().rstrip("\n")
        pub_key = key.read()
        service_name = f"{NAME}-{fingerprint}"
        service_name_deb = f"{NAME}-{fingerprint}-deb"
        try:
            AsciiArmoredDetachedSigningService.objects.get(name=service_name)
        except AsciiArmoredDetachedSigningService.DoesNotExist:
            print(f"Registering Signing service {service_name}")
            AsciiArmoredDetachedSigningService.objects.create(
                name=service_name,
                public_key=pub_key,
                pubkey_fingerprint=fingerprint,
                script=script_path,
            )
        else:
            print(f"Signing service {service_name} already present")

        try:
            print(f"Registering Signing service {service_name_deb}")
            AptReleaseSigningService.objects.create(
                name=service_name_deb,
                public_key=pub_key,
                pubkey_fingerprint=fingerprint,
                script=script_path,
            )
        except Exception as e:
            print(f"Cought exception while creating AptReleaseSigningService: {e}")
