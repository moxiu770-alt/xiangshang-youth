package com.xiangshang.youth.feature.auth

import android.content.Intent
import androidx.core.net.toUri
import androidx.compose.foundation.Image
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.xiangshang.youth.BuildConfig
import com.xiangshang.youth.R
import com.xiangshang.youth.app.*
import com.xiangshang.youth.core.model.LegalPolicy
import com.xiangshang.youth.core.model.UserRole
import com.xiangshang.youth.core.util.AuthIdentity
import com.xiangshang.youth.shared.component.AppScaffold
import kotlinx.coroutines.delay

@Composable
fun SplashScreen(onFinished: () -> Unit, canFinish: () -> Boolean = { true }) {
    LaunchedEffect(Unit) {
        delay(2000)
        while (!canFinish()) delay(120)
        onFinished()
    }
    // The approved splash is a portrait poster. Preserve its complete artwork
    // on every aspect ratio rather than cropping the headline or children.
    Box(Modifier.fillMaxSize().background(Color(0xFF7452A5)), contentAlignment = Alignment.Center) {
        Image(
            painter = painterResource(R.drawable.launch_poster),
            contentDescription = "向上少年启动页",
            modifier = Modifier.fillMaxSize(),
            contentScale = ContentScale.Fit
        )
    }
}

@Composable
fun LoginScreen(
    onLogin: (String, String?, String?) -> Unit,
    onRegister: () -> Unit,
    onForgotPassword: () -> Unit = {},
    loading: Boolean = false,
    serverError: String? = null,
    onClearError: () -> Unit = {},
    onRequestCode: (String, String, (Boolean, String?) -> Unit) -> Unit = { _, _, result -> result(true, null) }
) {
    var method by rememberSaveable { mutableIntStateOf(0) }
    var phone by rememberSaveable { mutableStateOf("") }
    var account by rememberSaveable { mutableStateOf("") }
    var code by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var passwordVisible by rememberSaveable { mutableStateOf(false) }
    var agreement by rememberSaveable { mutableStateOf(false) }
    var codeSent by rememberSaveable { mutableStateOf(false) }
    var codeSending by rememberSaveable { mutableStateOf(false) }
    var codeCountdown by rememberSaveable { mutableIntStateOf(0) }
    var error by rememberSaveable { mutableStateOf<String?>(null) }
    var legalDocument by rememberSaveable { mutableStateOf<String?>(null) }
    LaunchedEffect(codeCountdown > 0) {
        while (codeSent && codeCountdown > 0) {
            delay(1000)
            codeCountdown -= 1
        }
    }
    fun submitLogin() {
        when {
            !agreement -> error = "请先阅读并同意用户服务协议、隐私政策和儿童个人信息保护声明。"
            method == 0 -> onLogin(AuthIdentity.wechatAuthorizationIdentifier, null, null)
            method == 1 && phone.filter(Char::isDigit).length != 11 -> error = "请输入有效的 11 位手机号。"
            method == 1 && !codeSent -> error = "请先获取短信验证码。"
            method == 1 && code.length != 6 -> error = "请输入 6 位短信验证码。"
            method == 2 && account.isBlank() -> error = "请输入账号或手机号。"
            method == 2 && password.length < 8 -> error = "密码至少需要 8 位。"
            else -> onLogin(if (method == 1) phone else account, if (method == 1) code else null, if (method == 2) password else null)
        }
    }
    BoxWithConstraints(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color(0xFF76B8F7), Color(0xFFEFF8FF))))) {
        // Keep the supplied portrait composition readable on tablets without
        // stranding the footer midway down a large screen. Small-height and
        // landscape windows retain a scrollable, content-sized layout.
        // At accessibility font scales the content must remain scrollable even
        // on a tall tablet; anchoring is only a normal-text layout refinement.
        val accessibilityText = LocalConfiguration.current.fontScale >= 1.4f
        val anchoredTabletLayout = maxWidth >= 600.dp && maxHeight >= 800.dp && LocalConfiguration.current.fontScale <= 1.15f
        // Match the portrait reference on tall phones: the account card is a
        // deliberate primary surface, not a compact block floating over a
        // large empty gap. Short screens still use content height and scroll.
        // A 54% card keeps agreement and safeguards visible while avoiding an
        // oversized empty lower panel on 19.5:9 / 20:9 phones.
        val loginPanelMinHeight = if (!accessibilityText && maxWidth < 600.dp && maxHeight >= 720.dp) maxHeight * 0.50f else 0.dp
        // Preserve the portrait login composition on tablets instead of turning
        // the reference card into a very wide desktop form.
        Column(
            Modifier
                .widthIn(max = 620.dp)
                .fillMaxWidth()
                .align(Alignment.TopCenter)
                // A fixed tall-tablet column lets the weighted spacer anchor
                // the footer. Phone/small-height windows keep their scroll
                // container so keyboard and large-text content stays reachable.
                .then(
                    if (anchoredTabletLayout) Modifier.height(maxHeight)
                    else Modifier.verticalScroll(rememberScrollState())
                ),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Column(Modifier.padding(top = 34.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("向上少年", color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.Black)
                Text("身心健康智慧平台", color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Black)
                Text("学校体测 · 家庭健康记录 · 成长训练", color = Color(0xFFFFBD2E), fontSize = 16.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp).background(Color.White.copy(.17f), CircleShape))
            }
            Spacer(Modifier.height(10.dp))
            Surface(Modifier.fillMaxWidth().padding(horizontal = 10.dp).heightIn(min = loginPanelMinHeight), color = Color.White, shape = RoundedCornerShape(26.dp), shadowElevation = 4.dp) {
                Column(Modifier.fillMaxWidth().fillMaxHeight().padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) { Text("欢迎登录", color = Navy, fontSize = 16.sp, fontWeight = FontWeight.Bold) }
                    Column(verticalArrangement = Arrangement.spacedBy(7.dp), modifier = Modifier.fillMaxWidth()) {
                        LoginButton(if (loading && method == 0) "正在授权…" else "微信登录", Icons.Filled.ChatBubble, Blue, Color.White, { if (!loading) { if (method == 0) submitLogin() else { method = 0; error = null; onClearError() } } }, showsProgress = loading && method == 0)
                        LoginButton("手机号登录", Icons.Filled.PhoneIphone, Blue, Color.White, { if (!loading) { method = 1; error = null; onClearError() } }, outlined = method != 1)
                        LoginButton("账号密码登录", Icons.Filled.Person, Color(0xFFFFB92E), Color(0xFF765522), { if (!loading) { method = 2; error = null; onClearError() } }, outlined = method != 2)
                    }
                    if (method == 1) {
                        OutlinedTextField(value = phone, onValueChange = { value -> phone = value; error = null; onClearError(); if (codeSent || codeCountdown > 0 || code.isNotEmpty()) { codeSent = false; codeCountdown = 0; code = "" } }, label = { Text("手机号") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone), singleLine = true, modifier = Modifier.fillMaxWidth())
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            OutlinedTextField(value = code, onValueChange = { code = it; error = null; onClearError() }, label = { Text("短信验证码") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), singleLine = true, modifier = Modifier.weight(1f))
                        TextButton(onClick = {
                            if (phone.filter(Char::isDigit).length != 11) error = "请先填写 11 位手机号。"
                            else { codeSending = true; onRequestCode(phone, "login") { sent, message -> codeSending = false; if (sent) { codeSent = true; codeCountdown = 60; error = null } else error = message ?: "验证码发送失败，请稍后重试。" } }
                        }, enabled = codeCountdown == 0 && !codeSending) { Text(if (codeSending) "发送中…" else if (codeCountdown > 0) "${codeCountdown}s 后重试" else if (codeSent) "重新获取" else "获取验证码", fontSize = 16.sp) }
                        }
                    } else if (method == 2) {
                        OutlinedTextField(value = account, onValueChange = { account = it; error = null; onClearError() }, label = { Text("账号 / 手机号") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                        PasswordField(value = password, onValueChange = { password = it; error = null; onClearError() }, label = "登录密码（至少 8 位）", visible = passwordVisible, onVisibilityChanged = { passwordVisible = it }, modifier = Modifier.fillMaxWidth())
                    }
                    if (method != 0) Button(onClick = ::submitLogin, enabled = !loading, modifier = Modifier.fillMaxWidth().height(44.dp), shape = CircleShape) {
                        if (loading) CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(18.dp)) else Icon(Icons.AutoMirrored.Filled.ArrowForward, null)
                        Spacer(Modifier.width(7.dp)); Text(if (loading) "正在登录…" else "登录", fontWeight = FontWeight.Bold)
                    }
                    (error ?: serverError)?.let { Text(it, color = Color.Red, fontSize = 16.sp) }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        TextButton(onClick = onRegister, contentPadding = PaddingValues(0.dp)) { Text("家长注册", color = Blue, fontSize = 16.sp) }
                        TextButton(onClick = onForgotPassword, contentPadding = PaddingValues(0.dp)) { Text("忘记密码？", color = Color.Gray, fontSize = 16.sp) }
                    }
                    if (accessibilityText) {
                        Text("登录后可查看孩子的测评、健康记录和训练建议。", color = Color.Gray, fontSize = 16.sp, modifier = Modifier.fillMaxWidth().padding(top = 5.dp))
                    } else {
                        Column(Modifier.fillMaxWidth().padding(top = 5.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { LoginCheck("学校体测结果", "查看测评任务与报告"); LoginCheck("家庭健康记录", "完成居家观察与身体测评"); LoginCheck("成长训练建议", "按孩子报告安排每日训练") }
                    }
                    Spacer(Modifier.weight(1f, fill = true))
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Row(Modifier.weight(1f).semantics { role = Role.Checkbox; contentDescription = if (agreement) "已同意用户服务协议、隐私政策和儿童个人信息保护声明" else "同意用户服务协议、隐私政策和儿童个人信息保护声明" }.clickable { agreement = !agreement }) {
                            Checkbox(checked = agreement, onCheckedChange = { agreement = it })
                            Text(if (agreement) "已阅读并同意相关协议" else "请阅读并同意相关协议", color = if (agreement) Green else Color.Gray, fontSize = 16.sp)
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
                            TextButton(onClick = { legalDocument = LegalPolicy.USER_AGREEMENT_TITLE }, contentPadding = PaddingValues(0.dp)) { Text("用户服务协议", color = Blue, fontSize = 16.sp) }
                            TextButton(onClick = { legalDocument = "隐私政策" }, contentPadding = PaddingValues(0.dp)) { Text("隐私政策", color = Blue, fontSize = 16.sp) }
                            TextButton(onClick = { legalDocument = LegalPolicy.CHILD_PRIVACY_TITLE }, contentPadding = PaddingValues(0.dp), modifier = Modifier.semantics { contentDescription = "查看儿童个人信息保护声明" }) { Text("儿童保护声明", color = Blue, fontSize = 16.sp) }
                        }
                    }
                }
            }
            if (anchoredTabletLayout) Spacer(Modifier.weight(1f)) else Spacer(Modifier.height(18.dp))
            Image(painterResource(R.drawable.campus_footer), null, Modifier.widthIn(max = 560.dp).fillMaxWidth().height(112.dp), contentScale = ContentScale.Fit)
            Spacer(Modifier.height(3.dp))
        }
    }
    legalDocument?.let { document -> LegalDocumentDialog(document) { legalDocument = null } }
}

private fun legalText(document: String): String = LegalPolicy.document(document)

@Composable
fun RegisterScreen(
    onBack: () -> Unit,
    onRegistered: (name: String, phone: String, verificationCode: String, password: String, role: UserRole) -> Unit,
    loading: Boolean = false,
    serverError: String? = null,
    onClearError: () -> Unit = {},
    onRequestCode: (String, String, (Boolean, String?) -> Unit) -> Unit = { _, _, result -> result(true, null) }
) {
    var name by rememberSaveable { mutableStateOf("") }
    var phone by rememberSaveable { mutableStateOf("") }
    var code by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var passwordVisible by rememberSaveable { mutableStateOf(false) }
    var agreement by rememberSaveable { mutableStateOf(false) }
    var error by rememberSaveable { mutableStateOf<String?>(null) }
    var submitting by rememberSaveable { mutableStateOf(false) }
    var codeSent by rememberSaveable { mutableStateOf(false) }
    var codeCountdown by rememberSaveable { mutableIntStateOf(0) }
    var codeSending by rememberSaveable { mutableStateOf(false) }
    var legalDocument by rememberSaveable { mutableStateOf<String?>(null) }
    val accountRole = UserRole.Parent
    LaunchedEffect(codeCountdown > 0) {
        while (codeCountdown > 0) {
            delay(1000)
            codeCountdown -= 1
        }
    }
    LaunchedEffect(serverError) {
        if (serverError != null) {
            submitting = false
            error = serverError
        }
    }
    AppScaffold(title = "注册账号", onBack = onBack) {
        if (submitting) {
            Column(Modifier.fillMaxWidth().padding(top = 80.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                if (loading) CircularProgressIndicator(color = Blue, modifier = Modifier.size(48.dp)) else Icon(Icons.Filled.CheckCircle, null, tint = Green, modifier = Modifier.size(54.dp))
                Text(if (loading) "正在创建账号" else "账号已创建", color = Navy, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 12.dp))
                Text(if (loading) "正在进入${accountRole.label}工作区…" else "已归入${accountRole.label}账户", color = Color.Gray, fontSize = 16.sp, modifier = Modifier.padding(top = 6.dp))
            }
            return@AppScaffold
        }
        Text("创建向上少年账号", color = Navy, fontSize = 21.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 16.dp))
        Text("注册后可绑定家庭、接收学校通知并保存成长档案。", color = Color.Gray, fontSize = 16.sp, modifier = Modifier.padding(top = 5.dp, bottom = 14.dp))
        Text("账户类型", color = Navy, fontSize = 16.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 2.dp, bottom = 7.dp))
        Surface(shape = RoundedCornerShape(14.dp), color = Blue.copy(alpha = 0.10f), border = BorderStroke(1.dp, Blue), modifier = Modifier.fillMaxWidth().semantics { contentDescription = "家庭账户" }) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 11.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Home, null, tint = Blue)
                Column(Modifier.padding(start = 10.dp)) {
                    Text("家庭账户", color = Navy, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    Text("绑定孩子、查看测评报告与训练计划。教师和学校管理账号由学校管理员创建。", color = Color.Gray, fontSize = 16.sp, modifier = Modifier.padding(top = 2.dp))
                }
            }
        }
        OutlinedTextField(value = name, onValueChange = { name = it; error = null }, label = { Text("姓名") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(value = phone, onValueChange = { value -> phone = value; error = null; if (codeSent || codeCountdown > 0 || code.isNotEmpty()) { codeSent = false; codeCountdown = 0; code = "" } }, label = { Text("手机号") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone), singleLine = true, modifier = Modifier.fillMaxWidth().padding(top = 9.dp))
        Row(Modifier.fillMaxWidth().padding(top = 9.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(value = code, onValueChange = { code = it; error = null }, label = { Text("短信验证码") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), singleLine = true, modifier = Modifier.weight(1f))
            TextButton(onClick = {
                if (phone.filter(Char::isDigit).length != 11) error = "请先填写 11 位手机号。"
                else { codeSending = true; onRequestCode(phone, "register") { sent, message -> codeSending = false; if (sent) { codeSent = true; codeCountdown = 60; error = null } else error = message ?: "验证码发送失败，请稍后重试。" } }
            }, enabled = codeCountdown == 0 && !codeSending) { Text(if (codeSending) "发送中…" else if (codeCountdown > 0) "${codeCountdown}s" else if (codeSent) "重新获取" else "获取验证码", fontSize = 16.sp) }
        }
        PasswordField(value = password, onValueChange = { password = it; error = null }, label = "设置密码（至少 8 位）", visible = passwordVisible, onVisibilityChanged = { passwordVisible = it }, modifier = Modifier.fillMaxWidth().padding(top = 9.dp))
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 8.dp).semantics { role = Role.Checkbox; contentDescription = if (agreement) "已同意用户服务协议、隐私政策和儿童个人信息保护声明" else "同意用户服务协议、隐私政策和儿童个人信息保护声明" }.clickable { agreement = !agreement }) { Checkbox(checked = agreement, onCheckedChange = { agreement = it }); Text("我已阅读并同意用户服务协议、隐私政策和儿童个人信息保护声明", color = Navy, fontSize = 16.sp) }
        Row(horizontalArrangement = Arrangement.spacedBy(3.dp), modifier = Modifier.padding(top = 2.dp)) {
            TextButton(onClick = { legalDocument = LegalPolicy.USER_AGREEMENT_TITLE }, contentPadding = PaddingValues(0.dp)) { Text("用户服务协议", color = Blue, fontSize = 16.sp) }
            TextButton(onClick = { legalDocument = "隐私政策" }, contentPadding = PaddingValues(0.dp)) { Text("隐私政策", color = Blue, fontSize = 16.sp) }
            TextButton(onClick = { legalDocument = LegalPolicy.CHILD_PRIVACY_TITLE }, contentPadding = PaddingValues(0.dp)) { Text("儿童个人信息保护声明", color = Blue, fontSize = 16.sp) }
        }
        error?.let { Text(it, color = Color.Red, fontSize = 16.sp) }
        Button(onClick = {
            when {
                name.isBlank() -> error = "请输入姓名。"
                phone.filter(Char::isDigit).length != 11 -> error = "请输入有效的 11 位手机号。"
                !codeSent -> error = "请先获取短信验证码。"
                code.length != 6 -> error = "请输入 6 位短信验证码。"
                password.length < 8 -> error = "密码至少需要 8 位。"
                !agreement -> error = "请先同意相关协议。"
                else -> {
                    error = null
                    submitting = true
                    onClearError()
                    onRegistered(name.trim(), phone, code, password, accountRole)
                }
            }
        }, enabled = agreement && !loading, modifier = Modifier.fillMaxWidth().padding(top = 12.dp).height(44.dp), shape = CircleShape) { Text("注册并登录", fontWeight = FontWeight.Bold) }
    }
    legalDocument?.let { document -> LegalDocumentDialog(document) { legalDocument = null } }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LegalDocumentDialog(document: String, onDismiss: () -> Unit) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(modifier = Modifier.fillMaxSize(), color = Color(0xFFF7F9FC)) {
            Column {
                TopAppBar(
                    title = { Text(document, fontWeight = FontWeight.Bold) },
                    actions = {
                        IconButton(onClick = onDismiss, modifier = Modifier.semantics { contentDescription = "关闭$document" }) {
                            Icon(Icons.Filled.Close, contentDescription = null)
                        }
                    }
                )
                HorizontalDivider()
                Text(
                    legalText(document),
                    color = Navy,
                    fontSize = 16.sp,
                    lineHeight = 23.sp,
                    modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp, vertical = 20.dp)
                )
            }
        }
    }
}

private fun accountRoleDescription(role: UserRole): String = when (role) {
    UserRole.Parent -> "绑定孩子，查看测评报告与训练计划"
    UserRole.Teacher -> "管理班级测评任务、状态与复核"
            UserRole.Principal -> "学校管理数据请在后台看板查看"
}

@Composable
fun PasswordResetScreen(onBack: () -> Unit, onReset: (String, String, String, (Boolean, String?) -> Unit) -> Unit = { _, _, _, _ -> }, serverError: String? = null, onRequestCode: (String, String, (Boolean, String?) -> Unit) -> Unit = { _, _, result -> result(true, null) }) {
    var phone by rememberSaveable { mutableStateOf("") }
    var code by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var confirmation by rememberSaveable { mutableStateOf("") }
    var passwordVisible by rememberSaveable { mutableStateOf(false) }
    var confirmationVisible by rememberSaveable { mutableStateOf(false) }
    var codeSent by rememberSaveable { mutableStateOf(false) }
    var codeCountdown by rememberSaveable { mutableIntStateOf(0) }
    var error by rememberSaveable { mutableStateOf<String?>(null) }
    var submitted by rememberSaveable { mutableStateOf(false) }
    var codeSending by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(codeCountdown > 0) {
        while (codeCountdown > 0) {
            delay(1000)
            codeCountdown -= 1
        }
    }
    LaunchedEffect(serverError) { if (serverError != null) { error = serverError; submitted = false } }

    AppScaffold(title = "忘记密码", onBack = onBack) {
        if (submitted) {
            Column(
                Modifier.fillMaxWidth().padding(top = 80.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Icon(Icons.Filled.CheckCircle, null, tint = Green, modifier = Modifier.size(56.dp))
                Text("密码已重置", color = Navy, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 12.dp))
                Text("请使用新密码重新登录。", color = Color.Gray, fontSize = 16.sp, modifier = Modifier.padding(top = 6.dp))
                Button(onClick = onBack, modifier = Modifier.padding(top = 20.dp), shape = CircleShape) { Text("返回登录") }
            }
            return@AppScaffold
        }

        Text("找回向上少年账号", color = Navy, fontSize = 21.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 16.dp))
        Text("验证手机号后设置新密码，验证码将通过短信发送。", color = Color.Gray, fontSize = 16.sp, modifier = Modifier.padding(top = 5.dp, bottom = 14.dp))
        OutlinedTextField(
            value = phone,
            onValueChange = { value -> phone = value; error = null; if (codeSent || codeCountdown > 0 || code.isNotEmpty()) { codeSent = false; codeCountdown = 0; code = "" } },
            label = { Text("手机号") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )
        Row(Modifier.fillMaxWidth().padding(top = 9.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(
                value = code,
                onValueChange = { code = it; error = null },
                label = { Text("短信验证码") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                singleLine = true,
                modifier = Modifier.weight(1f)
            )
            TextButton(
                onClick = {
                    if (phone.filter(Char::isDigit).length != 11) error = "请输入有效的 11 位手机号。"
                    else { codeSending = true; onRequestCode(phone, "reset-password") { sent, message -> codeSending = false; if (sent) { codeSent = true; codeCountdown = 60; error = null } else error = message ?: "验证码发送失败，请稍后重试。" } }
                },
                enabled = codeCountdown == 0 && !codeSending
            ) { Text(if (codeSending) "发送中…" else if (codeCountdown > 0) "${codeCountdown}s" else if (codeSent) "重新获取" else "获取验证码", fontSize = 16.sp) }
        }
        PasswordField(value = password, onValueChange = { password = it; error = null }, label = "新密码（至少 8 位）", visible = passwordVisible, onVisibilityChanged = { passwordVisible = it }, modifier = Modifier.fillMaxWidth().padding(top = 9.dp))
        PasswordField(value = confirmation, onValueChange = { confirmation = it; error = null }, label = "再次输入新密码", visible = confirmationVisible, onVisibilityChanged = { confirmationVisible = it }, modifier = Modifier.fillMaxWidth().padding(top = 9.dp))
        error?.let { Text(it, color = Color.Red, fontSize = 16.sp, modifier = Modifier.padding(top = 8.dp)) }
        Button(
            onClick = {
                when {
                    phone.filter(Char::isDigit).length != 11 -> error = "请输入有效的 11 位手机号。"
                    !codeSent -> error = "请先获取短信验证码。"
                    code.length != 6 -> error = "请输入 6 位短信验证码。"
                    password.length < 8 -> error = "新密码至少需要 8 位。"
                    password != confirmation -> error = "两次输入的密码不一致。"
                    else -> { error = null; onReset(phone, code, password) { success, message -> submitted = success; if (!success) error = message ?: "密码重置失败，请稍后重试。" } }
                }
            },
            modifier = Modifier.fillMaxWidth().padding(top = 14.dp).height(44.dp),
            shape = CircleShape
        ) { Text("确认重置密码", fontWeight = FontWeight.Bold) }
    }
}

@Composable
private fun PasswordField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    visible: Boolean,
    onVisibilityChanged: (Boolean) -> Unit,
    modifier: Modifier = Modifier
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
        visualTransformation = if (visible) VisualTransformation.None else PasswordVisualTransformation(),
        singleLine = true,
        trailingIcon = {
            IconButton(onClick = { onVisibilityChanged(!visible) }) {
                Icon(
                    if (visible) Icons.Filled.VisibilityOff else Icons.Filled.Visibility,
                    contentDescription = if (visible) "隐藏密码" else "显示密码"
                )
            }
        },
        modifier = modifier
    )
}

@Composable private fun LoginButton(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, background: Color, foreground: Color, onClick: () -> Unit, outlined: Boolean = false, showsProgress: Boolean = false) = Surface(
    onClick = onClick, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).semantics { role = Role.Button; contentDescription = title }, color = background, shape = CircleShape, border = if (outlined) BorderStroke(1.dp, foreground) else null
) { Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) { if (showsProgress) CircularProgressIndicator(Modifier.size(16.dp), color = foreground, strokeWidth = 2.dp) else Icon(icon, null, tint = foreground, modifier = Modifier.size(16.dp)); Spacer(Modifier.width(7.dp)); Text(title, color = foreground, fontSize = 15.sp, fontWeight = FontWeight.Bold) } }
@Composable private fun LoginCheck(title: String, note: String) = Row(verticalAlignment = Alignment.CenterVertically) { Surface(Modifier.size(18.dp), color = Green, shape = CircleShape) { Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.padding(4.dp)) }; Spacer(Modifier.width(8.dp)); Column { Text(title, color = Navy, fontSize = 16.sp, fontWeight = FontWeight.Bold); Text(note, color = Color.Gray, fontSize = 16.sp) } }

@Composable
fun BackendDashboardNoticeScreen(onBack: (() -> Unit)? = null, onLogout: () -> Unit) {
    val context = LocalContext.current
    var openError by rememberSaveable { mutableStateOf<String?>(null) }
    val adminURL = BuildConfig.API_BASE_URL.trim().trimEnd('/').takeIf {
        it.startsWith("https://") && !it.equals("https://api.example.com", ignoreCase = true)
    }?.let { "$it/admin" }
    AppScaffold(title = "学校管理看板", onBack = onBack) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 54.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(Icons.Filled.BarChart, contentDescription = null, tint = Blue, modifier = Modifier.size(58.dp))
            Text("学校管理数据看板已迁移至后台系统", color = Navy, fontSize = 19.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 16.dp))
            Text("校长端不再作为移动端工作台提供。学校总览、年级对比、班级完成率和风险学生数据，请在学校后台数据看板中查看。", color = Color.Gray, fontSize = 16.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 10.dp))
            Button(
                onClick = {
                    val target = adminURL
                    if (target == null) openError = "当前版本尚未配置学校后台地址，请联系平台管理员。"
                    else runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, target.toUri())) }
                        .onFailure { openError = "无法打开学校后台，请稍后重试。" }
                },
                enabled = adminURL != null,
                modifier = Modifier.fillMaxWidth().padding(top = 18.dp).height(44.dp),
                shape = CircleShape
            ) { Text(if (adminURL == null) "后台地址待配置" else "打开学校管理后台") }
            openError?.let { Text(it, color = Color(0xFFD32F2F), fontSize = 16.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp)) }
            Button(onClick = onLogout, modifier = Modifier.fillMaxWidth().padding(top = 28.dp).height(44.dp), shape = CircleShape) { Text("退出当前账号") }
        }
    }
}

@Composable
fun RoleSelectScreen(availableRoles: List<UserRole> = emptyList(), onRole: (UserRole) -> Unit, onLogout: () -> Unit = {}) {
    var appeared by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { appeared = true }
    BoxWithConstraints(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.White, Sky)))) {
        val anchoredTabletLayout = maxWidth >= 600.dp && maxHeight >= 800.dp && LocalConfiguration.current.fontScale <= 1.15f
        Column(
            Modifier
                .widthIn(max = 620.dp)
                .fillMaxWidth()
                .align(Alignment.TopCenter)
                .padding(horizontal = 19.dp)
                .then(
                    if (anchoredTabletLayout) Modifier.height(maxHeight)
                    else Modifier.verticalScroll(rememberScrollState())
                ),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Row(Modifier.padding(top = 45.dp), verticalAlignment = Alignment.CenterVertically) { Text("请选择进入方式", color = Blue, fontSize = 18.sp, fontWeight = FontWeight.Bold); Spacer(Modifier.width(8.dp)); Icon(Icons.Filled.WbSunny, null, tint = Color(0xFFFFBD2E)) }
            Spacer(Modifier.height(20.dp))
            if (UserRole.Parent in availableRoles) {
                RoleCard(R.drawable.family_entrance, "家庭端", "家长查看孩子测评与成长建议", Blue, Color.White, appeared) { onRole(UserRole.Parent) }
            }
            if (UserRole.Parent in availableRoles && UserRole.Teacher in availableRoles) Spacer(Modifier.height(18.dp))
            if (UserRole.Teacher in availableRoles) {
                RoleCard(R.drawable.school_entrance, "学校端", "教师管理班级测评与学生状态", Color.White, Blue, appeared) { onRole(UserRole.Teacher) }
            }
            if (UserRole.Parent !in availableRoles && UserRole.Teacher !in availableRoles && UserRole.Principal in availableRoles) {
                Button(onClick = { onRole(UserRole.Principal) }, modifier = Modifier.fillMaxWidth().height(48.dp), shape = RoundedCornerShape(14.dp)) {
                    Icon(Icons.Filled.BarChart, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("进入学校后台管理看板", fontWeight = FontWeight.SemiBold)
                }
            }
            Text("学校管理数据看板由后台系统提供", color = Color.Gray, fontSize = 16.sp, modifier = Modifier.padding(top = 3.dp))
            TextButton(onClick = onLogout) { Text("退出当前账号", color = Color.Gray, fontSize = 16.sp) }
            if (anchoredTabletLayout) Spacer(Modifier.weight(1f)) else Spacer(Modifier.height(16.dp))
            Image(painterResource(R.drawable.campus_footer), null, Modifier.widthIn(max = 560.dp).fillMaxWidth().height(132.dp), contentScale = ContentScale.Fit)
            Spacer(Modifier.height(4.dp))
        }
    }
}

@Composable private fun RoleCard(image: Int, title: String, detail: String, background: Color, foreground: Color, appeared: Boolean, onClick: () -> Unit) = Surface(
    onClick = onClick, modifier = Modifier.fillMaxWidth().height(112.dp).scale(if (appeared) 1f else .88f), color = background, shape = RoundedCornerShape(16.dp), border = if (background == Color.White) BorderStroke(1.dp, Color(0xFFFFBD2E)) else null
) { Row(Modifier.padding(17.dp), verticalAlignment = Alignment.CenterVertically) { Image(painterResource(image), null, Modifier.size(64.dp).clip(RoundedCornerShape(12.dp)), contentScale = ContentScale.Fit); Spacer(Modifier.width(17.dp)); Column(Modifier.weight(1f)) { Text(title, color = foreground, fontSize = 20.sp, fontWeight = FontWeight.Bold); Text(detail, color = if (background == Color.White) Color.Gray else Color.White.copy(.85f), fontSize = 16.sp) }; Icon(Icons.Filled.ChevronRight, null, tint = if (background == Color.White) Color(0xFFFFB620) else Color.White) } }
