package io.mocklane.sample

import android.net.Uri
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import io.mocklane.sample.demo.DemoResult
import io.mocklane.sample.demo.DemoRunner
import io.mocklane.sample.demo.DemoScenario
import io.mocklane.sample.demo.DemoScenarios
import io.mocklane.sample.integration.MocklaneBootstrap
import java.util.concurrent.Executors

class MainActivity : AppCompatActivity() {
    private lateinit var out: TextView
    private lateinit var runAllBtn: Button
    private lateinit var clearBtn: Button
    private val worker = Executors.newSingleThreadExecutor()
    private var busy = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        out = findViewById(R.id.out)
        runAllBtn = findViewById(R.id.runAllBtn)
        clearBtn = findViewById(R.id.clearBtn)

        val list = findViewById<RecyclerView>(R.id.scenarioList)
        list.layoutManager = LinearLayoutManager(this)
        list.adapter =
            ScenarioAdapter(DemoScenarios.all, enabled = MocklaneBootstrap.isEnabled()) { scenario ->
                runScenario(scenario)
            }

        runAllBtn.setOnClickListener { runAll() }
        clearBtn.setOnClickListener { out.text = "Ready." }

        if (!MocklaneBootstrap.isEnabled()) {
            out.text = "Release build — Mocklane disabled. Scenario actions are no-ops."
            runAllBtn.isEnabled = false
        }
    }

    private fun setBusy(next: Boolean) {
        busy = next
        runOnUiThread {
            runAllBtn.isEnabled = !next && MocklaneBootstrap.isEnabled()
            clearBtn.isEnabled = !next
            (findViewById<RecyclerView>(R.id.scenarioList).adapter as? ScenarioAdapter)?.setEnabled(
                !next && MocklaneBootstrap.isEnabled(),
            )
        }
    }

    private fun runScenario(scenario: DemoScenario) {
        if (busy) return
        setBusy(true)
        out.text = "Running ${scenario.id} …"
        worker.execute {
            val result = DemoRunner.run(scenario)
            runOnUiThread {
                showResult(result)
                setBusy(false)
            }
        }
    }

    private fun runAll() {
        if (busy) return
        setBusy(true)
        out.text = "Running all scenarios …\n"
        worker.execute {
            val lines = StringBuilder()
            DemoRunner.runAll { _, result ->
                lines.append("[${result.id}] ${if (result.ok) "OK" else "FAIL"}\n")
                runOnUiThread { out.text = lines.toString() }
            }
            lines.append("\n=== Run all complete ===")
            runOnUiThread {
                out.text = lines.toString()
                setBusy(false)
            }
        }
    }

    private fun showResult(result: DemoResult) {
        out.text = "[${result.id}] ${if (result.ok) "OK" else "FAIL"}\n${result.detail}"
    }

    override fun onDestroy() {
        worker.shutdownNow()
        super.onDestroy()
    }
}

private class ScenarioAdapter(
    private val items: List<DemoScenario>,
    private var enabled: Boolean,
    private val onRun: (DemoScenario) -> Unit,
) : RecyclerView.Adapter<ScenarioAdapter.Holder>() {
    class Holder(view: View) : RecyclerView.ViewHolder(view) {
        val title: TextView = view.findViewById(R.id.scenarioTitle)
        val path: TextView = view.findViewById(R.id.scenarioPath)
        val runBtn: Button = view.findViewById(R.id.scenarioRunBtn)
    }

    fun setEnabled(value: Boolean) {
        enabled = value
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
        val view =
            LayoutInflater.from(parent.context).inflate(R.layout.item_scenario, parent, false)
        return Holder(view)
    }

    override fun onBindViewHolder(holder: Holder, position: Int) {
        val scenario = items[position]
        holder.title.text = "${scenario.id} ${scenario.label}"
        holder.path.text = pathLabel(scenario)
        holder.runBtn.isEnabled = enabled
        holder.runBtn.setOnClickListener { onRun(scenario) }
    }

    override fun getItemCount(): Int = items.size

    private fun pathLabel(scenario: DemoScenario): String {
        if (scenario.kind == "sdk_log") return "POST /__mocklane/v1/log"
        val uri = Uri.parse(scenario.url)
        return "${scenario.method} ${uri.path}${uri.encodedQuery?.let { "?$it" } ?: ""}"
    }
}
