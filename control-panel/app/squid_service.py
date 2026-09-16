import os
import logging

logger = logging.getLogger("control-panel")

SQUID_CONTAINER_NAME = os.getenv("SQUID_CONTAINER_NAME", "egress-proxy")

def reconfigure_squid() -> tuple[bool, str]:
    """
    docker.sock 経由で Squid コンテナに対して `squid -k reconfigure` を実行する。
    """
    docker_socket = "/var/run/docker.sock"
    if not os.path.exists(docker_socket):
        msg = f"Docker ソケット ({docker_socket}) が見つかりません。コンテナ外またはローカルテスト環境での実行です。"
        logger.warning(msg)
        return True, msg

    try:
        import docker
        client = docker.DockerClient(base_url="unix://var/run/docker.sock")
        container = client.containers.get(SQUID_CONTAINER_NAME)
        exec_res = container.exec_run("squid -k reconfigure")
        exit_code = exec_res.exit_code
        output = exec_res.output.decode("utf-8", errors="replace") if exec_res.output else ""

        if exit_code == 0:
            msg = f"Squid 設定を動的に再読み込みしました (Exit: {exit_code})"
            logger.info(msg)
            return True, msg
        else:
            msg = f"Squid 設定の再読み込みに失敗しました (Exit: {exit_code}): {output}"
            logger.error(msg)
            return False, msg
    except Exception as e:
        msg = f"Squid コンテナ操作中にエラーが発生しました: {str(e)}"
        logger.error(msg)
        return False, msg
