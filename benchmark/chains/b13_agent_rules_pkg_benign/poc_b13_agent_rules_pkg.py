"""Оракул benign-твина B13."""

from benchmark.chains.b13_agent_rules_pkg.poc_b13_agent_rules_pkg import (
    B13AgentRulesPackageExploit,
)


class B13AgentRulesPackageBenignExploit(B13AgentRulesPackageExploit):
    @property
    def chain_id(self) -> str:
        return "b13_agent_rules_pkg_benign"
