package com.superkid.military.military_maintenance

import android.app.Activity
import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Bundle
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.io.File
import org.json.JSONObject

/** Test APK only. Exercise the ordinary Flutter screen with Android accessibility. */
class ManualUiInstrumentation : Instrumentation() {
    private var runId=""
    private var mode="manual"
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments);runId=arguments?.getString("qaRunId") ?: "";mode=arguments?.getString("mode") ?: "manual";start()
    }
    private fun nodes(root: AccessibilityNodeInfo?): List<AccessibilityNodeInfo> {
        if(root==null) return emptyList()
        val result=mutableListOf(root)
        for(i in 0 until root.childCount) result.addAll(nodes(root.getChild(i)))
        return result
    }
    private fun label(n: AccessibilityNodeInfo)=listOfNotNull(n.text?.toString(),n.contentDescription?.toString(),
        if(android.os.Build.VERSION.SDK_INT>=26) n.hintText?.toString() else null).firstOrNull {it.isNotBlank()} ?: ""
    private fun find(text:String, exact:Boolean=false): AccessibilityNodeInfo? =
        nodes(uiAutomation.rootInActiveWindow).firstOrNull { it.isVisibleToUser &&
            (if(exact) label(it)==text else label(it).contains(text)) }
    private fun waitFor(text:String, seconds:Int=20): AccessibilityNodeInfo {
        repeat(seconds*4) {find(text)?.let{return it};Thread.sleep(250)}
        error("missing_ui_element:$text")
    }
    private fun click(n:AccessibilityNodeInfo) {
        check(n.packageName==targetContext.packageName) {"unexpected_window"}
        if(n.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return
        val r=Rect();n.getBoundsInScreen(r)
        val t=android.os.SystemClock.uptimeMillis()
        for(action in listOf(MotionEvent.ACTION_DOWN,MotionEvent.ACTION_UP)) {
            val event=MotionEvent.obtain(t,t+40,action,r.exactCenterX(),r.exactCenterY(),0)
            event.source=android.view.InputDevice.SOURCE_TOUCHSCREEN
            uiAutomation.injectInputEvent(event,true);event.recycle()
        }
    }
    private fun saveScreen(name:String) {
        val bitmap=checkNotNull(uiAutomation.takeScreenshot())
        File(targetContext.filesDir,name).outputStream().use {bitmap.compress(Bitmap.CompressFormat.PNG,100,it)}
        bitmap.recycle()
    }
    private fun navigate(text:String) {
        if (text in listOf("차량 등록·설정", "책자 검색", "정비 분석") && find(text, true) == null) {
            navigate("더 보기")
            click(waitFor(text))
            return
        }
        if(find(text,true)==null) {
            find("메뉴 열기",true)?.let {click(it);Thread.sleep(300)}
        }
        repeat(10) {
            find(text,true)?.let {click(it);return}
            val width=targetContext.resources.displayMetrics.widthPixels
            val side=nodes(uiAutomation.rootInActiveWindow).firstOrNull {n->
                val r=Rect();n.getBoundsInScreen(r);n.isScrollable && n.isVisibleToUser && r.right<width/2}
            side?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
            Thread.sleep(250)
        }
        error("navigation_not_visible")
    }
    private fun bodyScroll() {
        val width=targetContext.resources.displayMetrics.widthPixels
        nodes(uiAutomation.rootInActiveWindow).firstOrNull {n->
            val r=Rect();n.getBoundsInScreen(r);n.isScrollable && n.isVisibleToUser && r.left>width/6 && r.width()>width/2
        }?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
        Thread.sleep(300)
    }
    private fun dashboard(report:MutableMap<String,Any>) {
        waitFor("종합 현황",60)
        waitFor("운용 차량 12대")
        waitFor("차량 사진 점검")
        waitFor("정비 결과 입력")
        waitFor("정비 질문하기")
        waitFor("다음 점검")
        saveScreen("manual-ui-source.png")
        val db=android.database.sqlite.SQLiteDatabase.openDatabase(File(targetContext.applicationInfo.dataDir,"app_flutter/military.sqlite").path,null,android.database.sqlite.SQLiteDatabase.OPEN_READONLY)
        try {
            for((table,expected) in listOf("vehicles" to 12,"operations" to 84,"maintenance" to 116)) {
                val key=if(table=="vehicles") "id" else "vehicle_id"
                val count=db.rawQuery("SELECT count(*) FROM $table WHERE $key LIKE 'MOCK-OPS-%'",null).use {it.moveToFirst();it.getInt(0)}
                check(count>=expected) {"presentation_count_$table:$count"}
                report[table+"Count"]=count
            }
        } finally {db.close()}
        report["dashboardActionsVisible"]=true
        report["nextInspectionVisible"]=true
    }
    private fun onboarding(report:MutableMap<String,Any>) {
        Thread.sleep(1200)
        val greeting = "어서 오세요!"
        val firstLaunch = find(greeting) != null
        if (!firstLaunch) {
            waitFor("종합 현황", 60)
            navigate("차량 등록·설정")
            click(waitFor("정비온 사용 안내"))
        }
        report["guideEntry"] = if (firstLaunch) "first_launch" else "replay"
        waitFor(greeting, 60)
        saveScreen("manual-ui-source.png")
        report["firstLaunchGuideVisible"] = firstLaunch
        click(waitFor("사용 안내 시작"))
        waitFor("다음 점검")
        report["exampleDashboardOpened"] = true
        for (title in listOf(
            "사진으로 상태 남기기", "정비 결과 기록하기", "정비 질문하기",
            "필요한 기능 찾기", "차량별 상태 보기", "달력으로 일정 보기",
            "정비 흐름 살펴보기", "책자에서 찾기", "내 차량 준비하기", "기록 보관하기"
        )) {
            click(waitFor("다음"))
            waitFor(title)
        }
        click(waitFor("안내 마치기"))
        waitFor("종합 현황")
        report["exampleGuideCompleted"] = true
        navigate("차량 등록·설정")
        click(waitFor("정비온 사용 안내"))
        click(waitFor("내 차량 등록하기"))
        waitFor("내 차량 등록")
        report["registrationOpened"] = true
        click(waitFor("정비온 사용 안내"))
        waitFor(greeting)
        report["replayOpened"] = true
        click(waitFor("건너뛰기"))
        waitFor("종합 현황")
        report["skipReturnsToApp"] = true
    }
    private fun books(report:MutableMap<String,Any>) {
        waitFor("종합 현황")
        navigate("책자 검색")
        click(waitFor("책자 직접 보기"))
        Thread.sleep(500)
        val db=android.database.sqlite.SQLiteDatabase.openDatabase(File(targetContext.filesDir,"rag/active/corpus.sqlite").path,null,android.database.sqlite.SQLiteDatabase.OPEN_READONLY)
        val names=try {db.rawQuery("SELECT file FROM documents ORDER BY id",null).use {c->val rows=mutableListOf<String>();while(c.moveToNext()) rows.add(c.getString(0));rows}} finally {db.close()}
        click(waitFor(names.first()))
        click(waitFor(names[4]))
        Thread.sleep(400)
        click(waitFor("페이지 열기"))
        waitFor("PDF 1쪽",30)
        report["wiringFirstPageOpened"]=true
        click(waitFor("다음 페이지"))
        waitFor("PDF 2쪽",30)
        report["nextPageOpened"]=true
        click(waitFor("이전 페이지"))
        waitFor("PDF 1쪽",30)
        report["previousPageOpened"]=true
        saveScreen("manual-ui-source.png")
    }
    private fun analysis(report:MutableMap<String,Any>) {
        waitFor("종합 현황")
        navigate("정비 분석")
        waitFor("총 정비 건수")
        val db=android.database.sqlite.SQLiteDatabase.openDatabase(File(targetContext.applicationInfo.dataDir,"app_flutter/military.sqlite").path,
            null,android.database.sqlite.SQLiteDatabase.OPEN_READONLY)
        val records=mutableListOf<JSONObject>()
        try {
            val all=mutableSetOf<String>()
            db.rawQuery("SELECT payload FROM vehicles",null).use {while(it.moveToNext()) all.add(JSONObject(it.getString(0)).getString("id"))}
            val registered=all.filter {!it.startsWith("MOCK-")}.toSet()
            val exampleScope=db.rawQuery("SELECT value FROM app_metadata WHERE key='dashboard_scope'",null).use {it.moveToFirst() && it.getString(0)=="examples"}
            val presentation=all.filter {it.startsWith("MOCK-OPS-")}.toSet()
            val active=if(exampleScope && presentation.isNotEmpty()) presentation else if(registered.isEmpty()) all else registered
            val today=java.text.SimpleDateFormat("yyyy-MM-dd",java.util.Locale.US).format(java.util.Date())
            db.rawQuery("SELECT payload FROM maintenance",null).use {while(it.moveToNext()) {
                val r=JSONObject(it.getString(0));val date=r.getString("date")
                if(r.getString("vehicleId") in active && date>="2026-01-01" && date<=today) records.add(r)
            }}
        } finally {db.close()}
        val cost=records.sumOf {it.getLong("cost")}
        val formatted=java.text.NumberFormat.getIntegerInstance(java.util.Locale.US).format(cost)+"원"
        check(find("${records.size}건")!=null && find(formatted)!=null) {"analysis_totals_mismatch"}
        report["analysisTotalsMatch"]=true;report["maintenanceCount"]=records.size;report["maintenanceCost"]=cost
        repeat(6) {if(find("월별 정비 건수")==null) bodyScroll()}
        check(find("정비 종류별 건수")!=null && find("월별 정비 건수")!=null) {"chart_sections_missing"}
        if(records.isNotEmpty()) {
            val months=records.map {it.getString("date").substring(0,7)}.toSet()
            val seen=mutableSetOf<String>()
            repeat(8) {
                seen.addAll(months.filter {find(it)!=null})
                if(!seen.containsAll(months)) bodyScroll()
            }
            check(seen.containsAll(months)) {"monthly_chart_labels_missing"}
        }
        report["systemAndMonthChartsVisible"]=true
        saveScreen("manual-ui-source.png")
        navigate("지난 분석 결과")
        waitFor("선택 차량")
        check(find("AI 분석 점수")!=null || find("예측 없음")!=null) {"prediction_label_missing"}
        check(find("점검 순서와 이유")!=null) {"priority_section_missing"}
        repeat(12) {if(find("이전 분석 결과")==null) bodyScroll()}
        waitFor("이전 분석 결과")
        report["inspectionPriorityVisible"]=true
        report["predictionHistoryVisible"]=true
        saveScreen("manual-ui-ml.png")
    }
    private fun chat(report:MutableMap<String,Any>) {
        report["scope"]="ordinary_app_ui_questions_saved_only"
        waitFor("종합 현황")
        navigate("정비 질문")
        waitFor("추천 질문")
        report["questionExamplesVisible"]=true
        click(waitFor("질문할 차량"))
        Thread.sleep(300)
        var choice=nodes(uiAutomation.rootInActiveWindow).firstOrNull {it.isVisibleToUser && (label(it).contains("운용 ") || label(it).contains("MOCK-")) && label(it).contains("렉스턴")}
        repeat(8) {
            if(choice==null) {
                nodes(uiAutomation.rootInActiveWindow).lastOrNull {it.isScrollable && it.isVisibleToUser}
                    ?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)
                Thread.sleep(200)
                choice=nodes(uiAutomation.rootInActiveWindow).firstOrNull {it.isVisibleToUser && (label(it).contains("운용 ") || label(it).contains("MOCK-")) && label(it).contains("렉스턴")}
            }
        }
        click(choice ?: error("chat_supported_vehicle_missing"))
        Thread.sleep(400)
        click(waitFor("브레이크 패드를 분리할 때 주의사항은?",20))
        Thread.sleep(600) // Wait for Flutter to enable the send button.
        click(waitFor("보내기",20))
        Thread.sleep(450)
        if(find("정비 중")!=null) {
            report["mascotLoadingVisible"]=true
            saveScreen("manual-ui-loading.png")
            Thread.sleep(250)
            saveScreen("manual-ui-loading-next.png")
        }
        // Auto-scroll settles at the response end. Scroll back to locate citations.
        Thread.sleep(3000)
        repeat(120) {
            if(find("확인 중…",true)!=null) Thread.sleep(500)
        }
        repeat(8) {
            val width=targetContext.resources.displayMetrics.widthPixels
            nodes(uiAutomation.rootInActiveWindow).firstOrNull {n->
                val r=Rect();n.getBoundsInScreen(r);n.isScrollable && n.isVisibleToUser && r.left>width/6 && r.width()>width/2
            }?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)
            Thread.sleep(100)
        }
        var source=find("출처:")
        repeat(10) {if(source==null) {bodyScroll();source=find("출처:")}}
        check(source!=null) {"chat_cited_response_missing"}
        report["groundedReplyVisible"]=true
        if(mode=="chat-images") {
            var image=find("페이지 이미지 확대")
            repeat(10) {if(image==null) {bodyScroll();image=find("페이지 이미지 확대")}}
            check(image!=null) {"cited_image_preview_missing"}
            report["imagePreviewVisible"]=true
            saveScreen("manual-ui-ml.png")
            click(image!!)
            waitFor("그림 닫기")
            click(find("확대",true) ?: error("image_zoom_button_missing"))
            report["imageZoomOpened"]=true
            report["zoomControlUsed"]=true
            saveScreen("manual-ui-source.png")
            return
        }
        saveScreen("manual-ui-ml.png")
        click(source!!)
        waitFor("닫기")
        report["sourceDialogOpened"]=true
        saveScreen("manual-ui-source.png")
    }
    private fun frontModel(report: MutableMap<String, Any>) {
        val sample = File(targetContext.cacheDir, "front-vision-qa.jpg")
        check(sample.isFile) { "missing_front_vision_sample" }
        check(FrontPartSession.info(targetContext)["installed"] == true)
        val result = FrontPartSession(targetContext, 2).use { session ->
            JSONObject(session.infer(JSONObject().put("imagePath", sample.path).toString()))
        }
        check(result.getString("modelId") == FrontPartSession.ID)
        val proposals = result.getJSONArray("proposals")
        check(proposals.length() > 0) { "sample_front_parts_missing" }
        val parts = mutableListOf<String>()
        for (index in 0 until proposals.length()) {
            val proposal = proposals.getJSONObject(index)
            val box = proposal.getJSONArray("box")
            check(box.length() == 4 && (0 until 4).all { box.getDouble(it) in 0.0..1.0 })
            check(box.getDouble(0) < box.getDouble(2) && box.getDouble(1) < box.getDouble(3))
            parts.add(proposal.getString("part"))
        }
        check("grille" in parts) { "sample_grille_missing" }
        report["detectedPartNames"] = parts
    }

    override fun onStart() { Thread {
        val report=mutableMapOf<String,Any>("scope" to "ordinary_app_ui_read_only", "status" to "failed")
        var clipboard:android.content.ClipboardManager?=null
        var previousClip:android.content.ClipData?=null
        var clipboardChanged=false
        try {
            uiAutomation.serviceInfo=uiAutomation.serviceInfo.apply {
                flags=flags or android.accessibilityservice.AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                    android.accessibilityservice.AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            }
            val activity=startActivitySync(Intent().setClassName(targetContext.packageName,targetContext.packageName+".MainActivity")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            if(android.os.Build.VERSION.SDK_INT>=27) runOnMainSync {
                activity.setTurnScreenOn(true)
                val keyguard=targetContext.getSystemService(android.content.Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
                if(!keyguard.isKeyguardSecure) keyguard.requestDismissKeyguard(activity,null)
            }
            if(mode=="front-model") {
                frontModel(report)
            } else if(mode=="dashboard") {
                dashboard(report)
            } else if(mode=="onboarding") {
                onboarding(report)
            } else if(mode=="books") {
                books(report)
            } else if(mode=="analysis") {
                analysis(report)
            } else if(mode=="chat" || mode=="chat-images") {
                chat(report)
            } else {
            waitFor("종합 현황",60)
            navigate("책자 검색")
            repeat(80) {
                if(nodes(uiAutomation.rootInActiveWindow).any {n->n.isVisibleToUser && n.className=="android.widget.EditText"}) return@repeat
                Thread.sleep(250)
            }
            check(nodes(uiAutomation.rootInActiveWindow).any {it.isVisibleToUser && it.className=="android.widget.EditText"}) {"question_field_missing"}
            report["screenOpened"]=true
            val db=android.database.sqlite.SQLiteDatabase.openDatabase(
                File(targetContext.filesDir,"rag/active/corpus.sqlite").path,null,
                android.database.sqlite.SQLiteDatabase.OPEN_READONLY)
            val file=try {db.rawQuery("SELECT file FROM documents WHERE id='D03'",null).use {check(it.moveToFirst());it.getString(0)}} finally {db.close()}
            click(waitFor("전체 책자"));click(waitFor(file))
            click(waitFor("전체 부품"));click(waitFor("오일필터"))
            report["filtersSelected"]=true
            // Dropdown route semantics disappear after its close animation.
            repeat(80) {
                if(nodes(uiAutomation.rootInActiveWindow).any {n->n.isVisibleToUser && n.className=="android.widget.EditText"}) return@repeat
                Thread.sleep(100)
            }
            val edit=nodes(uiAutomation.rootInActiveWindow).first {it.isVisibleToUser && it.className=="android.widget.EditText"}
            click(edit)
            Thread.sleep(400)
            val question="오일 필터 엘리먼트를 분리할 때 파손에 주의할 부품은 무엇인가요"
            val focused=nodes(uiAutomation.rootInActiveWindow).first {it.isVisibleToUser && it.className=="android.widget.EditText"}
            focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,question)
            })
            Thread.sleep(400)
            fun reflected()=nodes(uiAutomation.rootInActiveWindow).any {it.isVisibleToUser && it.text?.toString()?.contains(question)==true}
            if(!reflected()) {
                clipboard=targetContext.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                previousClip=clipboard!!.primaryClip
                clipboardChanged=true
                clipboard!!.setPrimaryClip(android.content.ClipData.newPlainText("RAG QA",question))
                Thread.sleep(300)
                val input=nodes(uiAutomation.rootInActiveWindow).first {it.isVisibleToUser && it.className=="android.widget.EditText"}
                input.performAction(AccessibilityNodeInfo.ACTION_PASTE)
                repeat(20) {if(!reflected()) Thread.sleep(100)}
            }
            check(reflected()) {"question_value_not_reflected"}
            report["koreanInputAccepted"]=true
            Thread.sleep(500)
            runOnMainSync {
                val ime=activity.getSystemService(android.content.Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
                ime.hideSoftInputFromWindow(activity.window.decorView.windowToken,0)
            }
            Thread.sleep(300)
            val search=find("검색",true) ?: error("search_button_missing")
            click(search)
            waitFor("질문 뜻과 입력한 말을 함께 살펴 찾기",40)
            waitFor("원문에 근거한 답변",60)
            report["hybridResultVisible"]=true
            report["citedAnswerVisible"]=true
            var source=find("인용 원문 전체 보기")
            repeat(5) {
                if(source==null) {
                    val scroll=nodes(uiAutomation.rootInActiveWindow).lastOrNull {it.isScrollable && it.isVisibleToUser}
                    scroll?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
                    Thread.sleep(300);source=find("인용 원문 전체 보기")
                }
            }
            click(source ?: error("source_button_missing"))
            waitFor("원본 파일 확인번호")
            report["sourceDialogOpened"]=true
            uiAutomation.takeScreenshot()?.let {bitmap->
                File(targetContext.filesDir,"manual-ui-source.png").outputStream().use {
                    bitmap.compress(Bitmap.CompressFormat.PNG,100,it)
                };bitmap.recycle()
            }
            }
            report["status"]="passed"
        } catch(e:Throwable) {
            report["error"]=e.message ?: e.javaClass.simpleName
            report["windowPackage"]=uiAutomation.rootInActiveWindow?.packageName?.toString() ?: "none"
            if(uiAutomation.rootInActiveWindow?.packageName==targetContext.packageName) {
                report["visibleLabels"]=nodes(uiAutomation.rootInActiveWindow).filter {it.isVisibleToUser}
                    .map {label(it)}.filter {it.isNotBlank()}.take(100)
                uiAutomation.takeScreenshot()?.let {bitmap->
                    File(targetContext.filesDir,"manual-ui-source.png").outputStream().use {bitmap.compress(Bitmap.CompressFormat.PNG,100,it)}
                    bitmap.recycle()
                }
            }
        }
        if(clipboardChanged) {
            if(previousClip!=null) clipboard!!.setPrimaryClip(previousClip!!)
            else if(android.os.Build.VERSION.SDK_INT>=28) clipboard!!.clearPrimaryClip()
        }
        report["qaRunId"]=runId
        report["mode"]=mode
        File(targetContext.filesDir,"manual-ui-result.json").writeText(JSONObject(report).toString(2))
        finish(if(report["status"]=="passed") Activity.RESULT_OK else Activity.RESULT_CANCELED,
            Bundle().apply {putString("status",report["status"].toString())})
    }.start() }
}
