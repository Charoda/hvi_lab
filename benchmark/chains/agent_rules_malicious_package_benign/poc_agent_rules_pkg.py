"""Оракул benign-твина вектора B2 — тот же критерий, ожидается SECURE."""

from benchmark.chains.agent_rules_malicious_package.poc_agent_rules_pkg import (
    AgentRulesPackageExploit,
)


class AgentRulesPackageBenignExploit(AgentRulesPackageExploit):
    @property
    def chain_id(self) -> str:
        return "agent_rules_malicious_package_benign"
